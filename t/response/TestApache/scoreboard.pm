package TestApache::scoreboard;

use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestUtil;
use Apache::TestTrace;

use Apache::Response ();
use Apache::RequestRec;
use Apache::Scoreboard;

use File::Spec::Functions qw(catfile);

use Apache::Const -compile => 'OK';

my @worker_score_scalar_props = qw(
    thread_num tid req_time most_recent status access_count
    bytes_served my_access_count my_bytes_served conn_bytes conn_count
    client request vhost
);

my @worker_score_dual_props = qw(
    times start_time stop_time
);


my $cfg = Apache::Test::config();
my $vars = $cfg->{vars};

my $store_file = catfile $vars->{documentroot}, "scoreboard";
my $hostport = Apache::TestRequest::hostport($cfg);
my $retrieve_url = "http://$hostport/scoreboard";

sub handler {
    my $r = shift;

    my $ntests = 15 + @worker_score_scalar_props + @worker_score_dual_props * 2;
    $ntests += 2 if $vars->{maxclients} > 1;

    plan $r, todo => [], tests => $ntests, ['status'];

    ### constants ###

    debug "PID: ", $$, " ppid:", getppid(), "\n";

    t_debug("constants");
    ok Apache::Const::SERVER_LIMIT;
    ok Apache::Const::THREAD_LIMIT;
    ok Apache::Scoreboard::REMOTE_SCOREBOARD_TYPE;

    ### the scoreboard image fetching methods ###

    # get the image internally
    my $image = Apache::Scoreboard->image($r->pool);
    ok $image && ref $image;

    # now fetch the image via lwp and run a few basic tests
    # need to have two availble workers, otherwise it'll hang
    # run the test with: -maxclients 2
    if ($vars->{maxclients} > 1) {
        t_debug("fetching: $retrieve_url");
        my $image = Apache::Scoreboard->fetch($r->pool, $retrieve_url);
        ok image_is_ok($image);

        t_debug("fetch_store/retrieve ($store_file)");
        Apache::Scoreboard->fetch_store($retrieve_url, $store_file);
        $image = Apache::Scoreboard->retrieve($r->pool, $store_file);
        ok image_is_ok($image);
    }

    # testing freeze/store/retrieve/thaw the scoreboard image
    {
        t_debug "image freeze/thaw";
        my $frozen_image = $image->freeze;
        my $thawed_image =  Apache::Scoreboard->thaw($r->pool, $frozen_image);
        ok image_is_ok($thawed_image);

        t_debug("image store/retrieve ($store_file)");
        Apache::Scoreboard->store($frozen_image, $store_file);
        my $image = Apache::Scoreboard->retrieve($r->pool, $store_file);
        ok image_is_ok($image);
    }

    ### parents/workers iteration functions ###

    t_debug "iterating over procs/workers";
    my $parent_ok      = 1;
    my $next_ok        = 1;
    my $next_live_ok   = 1;
    my $next_active_ok = 1;
    for (my $parent_score = $image->parent_score;
         $parent_score;
         $parent_score = $parent_score->next) {

        $parent_ok = 0 unless parent_score_is_ok($parent_score);

        my $pid = $parent_score->pid;
        t_debug "pid = $pid";

        # iterating over all workers for the given parent
        for (my $worker_score = $parent_score->worker_score;
                $worker_score;
                $worker_score = $parent_score->next_worker_score($worker_score)
            ) {
            $next_ok = 0 unless worker_score_is_ok($worker_score);
        }

        # iterating over only live workers for the given parent
        for (my $worker_score = $parent_score->worker_score;
                $worker_score;
                $worker_score = $parent_score->next_live_worker_score($worker_score)
            ) {
            $next_live_ok = 0 unless worker_score_is_ok($worker_score);
        }


        # iterating over only active workers for the given parent
        for (my $worker_score = $parent_score->worker_score;
                $worker_score;
                $worker_score = $parent_score->next_active_worker_score($worker_score)
            ) {
            $next_active_ok = 0 unless worker_score_is_ok($worker_score);
        }
    }
    t_debug "parent ok";
    ok $parent_ok;
    t_debug "iterating over all workers";
    ok $next_ok;
    t_debug "iterating over all live workers";
    ok $next_live_ok;
    t_debug "iterating over all active workers";
    ok $next_active_ok;


    ### other scoreboard image accessors ###

    my @pids = @{ $image->pids };
    t_debug "pids: @pids";
    ok @pids;

    my @thread_numbers = @{ $image->thread_numbers(0) };
    t_debug "thread_numbers: @thread_numbers";
    ok @thread_numbers;

    my $up_time = $image->up_time;
    t_debug "up_time: $up_time";
    ok $up_time;

    my $worker_score = $image->worker_score(0, 0);
    ok $worker_score;

    my $self_parent_idx = $image->parent_idx_by_pid($$);
    my $self_parent_score = $image->parent_score($self_parent_idx);
    t_debug "parent_idx_by_pid";
    ok parent_score_is_ok($self_parent_score);

    ### worker_score properties ###

    t_debug "worker_score properties:";
    for (@worker_score_dual_props) {
        my $res = $worker_score->$_();
        t_debug "$_ (scalar ctx): $res";
        ok defined $res;

        my @res = $worker_score->$_();
        t_debug "$_   (list ctx): @res";
        ok @res;

    }

    for (@worker_score_scalar_props) {
        my $res = $worker_score->$_();
        t_debug "$_: $res";
        ok defined $res;
    }

    Apache::OK;
}

# try to access various underlaying datastructures to test that the
# image is valid
sub image_is_ok {
    my ($image) = shift;
    return $image &&
           ref $image &&
           $image->pids &&
           $image->worker_score(0, 0)->status &&
           $image->parent_score &&
           $image->parent_score->worker_score->vhost;
}

# check that all worker_score props return something
sub parent_score_is_ok {
    my ($parent_score) = shift;

    my $ok = 1;

    $ok = 0 unless $parent_score && 
                   $parent_score->pid && 
                   $parent_score->worker_score;

    return $ok;
}

# check that all worker_score props return something
sub worker_score_is_ok {
    my ($worker_score) = shift;

    return 0 unless $worker_score;

    my $ok = 1;
    for (@worker_score_dual_props) {
        my $res = $worker_score->$_();
        $ok = 0 unless defined $res;

        my @res = $worker_score->$_();
        $ok = 0 unless @res;
    }

    for (@worker_score_scalar_props) {
        my $res = $worker_score->$_();
        $ok = 0 unless defined $res;
    }

    return $ok;
}

1;
