package TestInternal::basic;

use strict;
use warnings FATAL => 'all';

use Apache::Test;

use Apache::Response ();
use Apache::RequestRec ();

use Apache::Scoreboard ();
use MyTest::Common ();

use Apache::Const -compile => 'OK';

sub handler {
    my $r = shift;

    my $ntests = MyTest::Common::num_of_tests();

    plan $r, todo => [], tests => $ntests, ['status'];

    MyTest::Common::test1();

    # get the image internally (only under the live server)
    my $image = Apache::Scoreboard->image($r->pool);
    MyTest::Common::test2($image);

    Apache::OK;
}

1;
