package Apache::Scoreboard;

$Apache::Scoreboard::VERSION = '2.02';

use strict;
use warnings FATAL => 'all';

BEGIN {
    require mod_perl;
    die "This module was built against mod_perl 2.0 ",
        "and can't be used with $mod_perl::VERSION, "
            unless $mod_perl::VERSION > 1.98;
}

# so that it can be loaded w/o mod_perl (.e.g MakeMaker requires this
# file when Apache::Scoreboard is some other module's PREREQ_PM)
if ($ENV{MOD_PERL}) {
    require XSLoader;
    XSLoader::load(__PACKAGE__, $Apache::Scoreboard::VERSION);
}


use constant DEBUG => 0;

my $ua;

sub http_fetch {
    my($self, $url) = @_;

    require LWP::UserAgent;
    unless ($ua) {
	no strict 'vars';
	$ua = LWP::UserAgent->new;
	$ua->agent(join '/', __PACKAGE__, $VERSION);
    }

    my $request = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);
    unless ($response->is_success) {
	warn "request failed: ", $response->status_line if DEBUG;
	return undef;
    }

    # XXX: fixme
#    my $type = $response->header('Content-type');
#    unless ($type eq Apache::Scoreboard::REMOTE_SCOREBOARD_TYPE) {
#	warn "invalid scoreboard Content-type: $type" if DEBUG;
#	return undef;
#    }

    $response->content;
}

sub fetch {
    my($self, $pool, $url) = @_;
    $self->thaw($pool, $self->http_fetch($url));
}

sub fetch_store {
    my($self, $url, $file) = @_;
    $self->store($self->http_fetch($url), $file);
}

sub store {
    my($self, $frozen_image, $file) = @_;
    open my $fh, ">$file" or die "open $file: $!";
    print $fh $frozen_image;
    close $fh;
}

sub retrieve {
    my($self, $pool, $file) = @_;
    open my $fh, $file or die "open $file: $!";
    local $/;
    my $data = <$fh>;
    close $fh;
    $self->thaw($pool, $data);
}

1;
__END__

=head1 NAME

Apache::Scoreboard - Perl interface to the Apache scoreboard structure

=head1 SYNOPSIS

  use Apache::Scoreboard ();

  #inside httpd
  my $image = Apache::Scoreboard->image;

  #outside httpd
  my $image = Apache::Scoreboard->fetch("http://localhost/scoreboard");

=head1 DESCRIPTION

Apache keeps track of server activity in a structure known as the
I<scoreboard>.  There is a I<slot> in the scoreboard for each child
server, containing information such as status, access count, bytes
served and cpu time.  This same information is used by I<mod_status>
to provide current server statistics in a human readable form.

=head1 METHODS

=over 4

=item image

This method returns an object for accessing the scoreboard structure
when running inside the server:

  my $image = Apache::Scoreboard->image;

=item fetch

This method fetches the scoreboard structure from a remote server,
which must contain the following configuration:

 PerlModule Apache::Scoreboard
 <Location /scoreboard>
    SetHandler modperl
    PerlHandler Apache::Scoreboard::send
    order deny,allow
    deny from all
    #same config you have for mod_status
    allow from 127.0.0.1 ...
 </Location>

If the remote server is not configured to use mod_perl or simply for a 
smaller footprint, see the I<apxs> directory for I<mod_scoreboard_send>:

 LoadModule scoreboard_send_module libexec/mod_scoreboard_send.so

 <Location /scoreboard>
    SetHandler scoreboard-send-handler
    order deny,allow
    deny from all
    allow from 127.0.0.1 ...
 </Location>

The image can then be fetched via http:

  my $image = Apache::Scoreboard->fetch("http://remote-hostname/scoreboard");

=item fetch_store

=item retrieve

The I<fetch_store> method is used to fetch the image once from and
remote server and save it to disk.  The image can then be read by
other processes with the I<retrieve> function.
This way, multiple processes can access a remote scoreboard with just
a single request to the remote server.  Example: 

 Apache::Scoreboard->fetch_store($url, $local_filename);

 my $image = Apache::Scoreboard->retrieve($local_filename);

=item parent

This method returns a reference to the first parent score entry in the 
list, blessed into the I<Apache::ParentScore> class:

 my $parent = $image->parent;

Iterating over the list of scoreboard slots is done like so:

 for (my $parent = $image->parent; $parent; $parent = $parent->next) {
     my $pid = $parent->pid; #pid of the child

     my $server = $parent->server; #Apache::ServerScore object

     ...
 }

=item pids

Returns an array reference of all child pids:

 my $pids = $image->pids;

=back

=head2 The Apache::ParentScore Class

=over 4

=item pid

The parent keeps track of child pids with this field:

 my $pid = $parent->pid;

=item server

Returns a reference to the corresponding I<Apache::ServerScore>
structure:

 my $server = $parent->server;

=item next

Returns a reference to the next I<Apache::ParentScore> object in the list:

 my $p = $parent->next;

=back

=head2 The Apache::ServerScore Class

=over 4

=item status

This method returns the status of child server, which is one of:

 "_" Waiting for Connection
 "S" Starting up
 "R" Reading Request
 "W" Sending Reply
 "K" Keepalive (read)
 "D" DNS Lookup
 "L" Logging
 "G" Gracefully finishing
 "." Open slot with no current process

=item access_count

The access count of the child server:

 my $count = $server->access_count;

=item request

The first 64 characters of the HTTP request:

 #e.g.: GET /scoreboard HTTP/1.0
 my $request = $server->request;

=item client

The ip address or hostname of the client:

 #e.g.: 127.0.0.1
 my $client = $server->client;

=item bytes_served

Total number of bytes served by this child:

 my $bytes = $server->bytes_served;

=item conn_bytes

Number of bytes served by the last connection in this child:

 my $bytes = $server->conn_bytes;

=item conn_count

Number of requests served by the last connection in this child:

 my $count = $server->conn_count;

=item times

In a list context, returns a four-element list giving the user and
system times, in seconds, for this process and the children of this
process.

 my($user, $system, $cuser, $csystem) = $server->times;

In a scalar context, returns the overall CPU percentage for this server:

 my $cpu = $server->times;

=item start_time

In a list context this method returns a 2 element list with the seconds and
microseconds since the epoch, when the request was started.  In scalar
context it returns floating seconds like Time::HiRes::time()

 my($tv_sec, $tv_usec) = $server->start_time;

 my $secs = $server->start_time;

=item stop_time

In a list context this method returns a 2 element list with the seconds and
microseconds since the epoch, when the request was finished.  In scalar
context it returns floating seconds like Time::HiRes::time()

 my($tv_sec, $tv_usec) = $server->stop_time;

 my $secs = $server->stop_time;

=item req_time

Returns the time taken to process the request in microseconds:

 my $req_time = $server->req_time;

=back

=head1 SEE ALSO

Apache::VMonitor(3), GTop(3)

=head1 AUTHOR

Doug MacEachern
