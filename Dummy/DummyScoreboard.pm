package Apache::DummyScoreboard;

use strict;
use warnings FATAL => 'all';

$Apache::DummyScoreboard::VERSION = '2.00';
require XSLoader;
XSLoader::load(__PACKAGE__, $Apache::DummyScoreboard::VERSION);

1;
__END__

=head1 NAME

Apache::DummyScoreboard - Perl interface to the Apache scoreboard structure

=head1 DESCRIPTION

when loading C<Apache::Scoreboard>, C<Apache::DummyScoreboard> is used
internally if the code is not running under mod_perl. It has almost
the same functionality with some limitations. See the
C<Apache::Scoreboard> manpage for more info.

=head1 LIMITATIONS

=over

=item *

At the moment C<Apache::Const::SERVER_LIMIT> and
C<Apache::Const::THREAD_LIMIT> are hardwired to 0, since the methods
that provide this information are only accessible via a running Apache
(i.e. via C<Apache::Scoreboad> running under mod_perl).

=back

=cut

