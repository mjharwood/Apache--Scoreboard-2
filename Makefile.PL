use strict;
#use warnings;
use warnings FATAL => 'all';
#no warnings 'redefine';

use Apache2;
use mod_perl 1.99;

# XXX: need to check that the same perl is used as the one mod_perl
# was built with, otherwise unresolved symbols problems occur:
# e.g. try using mod_perl.so built with blead-perl and build the
# scoreboard with blead-ithreads-perl
#use Apache::Build ();
#my $build = Apache::Build->new;
#use lib qw(../lib ../Apache-Test/lib);

use ModPerl::MM ();

# enable 'make test|clean'
use Apache::TestMM qw(test clean);

# prerequisites
my %require = (
    "Apache::Test" => "1.10", # ipv6 fixes
    "mod_perl"     => "1.9917",
);

my @scripts = qw(t/TEST);

# accept the configs from command line
Apache::TestMM::filter_args();
Apache::TestMM::generate_script('t/TEST');

ModPerl::MM::WriteMakefile(
    NAME         => 'Apache::Scoreboard',
    VERSION_FROM => 'lib/Apache/Scoreboard.pm',
    PREREQ_PM    => \%require,
    clean        => {
        FILES => "@{ clean_files() }",
    }
);

sub clean_files {
    return \@scripts;
}


__END__
