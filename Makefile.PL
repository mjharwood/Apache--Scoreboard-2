use strict;
#use warnings;
use warnings FATAL => 'all';
no warnings 'redefine';

use Apache2;
use mod_perl 1.99;

use Apache::Build ();

my $build = Apache::Build->new;

use lib qw(../lib ../Apache-Test/lib);

use ModPerl::MM ();

# enable 'make test|clean'
use Apache::TestMM qw(test clean);

# prerequisites
my %require = (
    "Apache::Test" => "", # any version will do?
);

my @scripts = qw(t/TEST);

# accept the configs from comman line
Apache::TestMM::filter_args();
Apache::TestMM::generate_script('t/TEST');

ModPerl::MM::WriteMakefile(
    NAME         => 'Apache::Scoreboard',
    VERSION_FROM => 'Scoreboard.pm',
    #INC          => $build->inc,
    #DEFINE       => $build->define,
    PREREQ_PM    => \%require,
    clean        => {
        FILES => "@{ clean_files() }",
    });

sub clean_files {
    return \@scripts;
}


__END__
