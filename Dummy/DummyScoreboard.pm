package Apache::DummyScoreboard;

use strict;
use DynaLoader ();

{
    no strict;
    $VERSION = '0.04';
    @ISA = qw(DynaLoader);
    __PACKAGE__->bootstrap($VERSION);
}

1;
__END__
