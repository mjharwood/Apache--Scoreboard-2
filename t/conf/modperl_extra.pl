use Apache2;

use ModPerl::Util (); #for CORE::GLOBAL::exit

use Apache::RequestRec ();
use Apache::RequestIO ();
use Apache::RequestUtil ();

use Apache::Const -compile => ':common';
use APR::Const -compile => ':common';

unless ($ENV{MOD_PERL}) {
    die '$ENV{MOD_PERL} not set!';
}

1;
