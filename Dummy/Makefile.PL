use ExtUtils::MakeMaker;

use strict;
use warnings FATAL => 'all';

use ModPerl::MM ();

#mmm
system "cp ../typemap ." unless -e "typemap";

sub genxs {
    system "cat dummy.c ../Scoreboard.xs > DummyScoreboard.xs";
    system $^X, "-pi", "-e",
        "s/(MODULE *= *Apache::)Scoreboard/\$1.DummyScoreboard/e; " .
        "s|apxs/send.c|../apxs/send.c|;",
        "DummyScoreboard.xs";
}

genxs();

ModPerl::MM::WriteMakefile(
    NAME	 => 'Apache::DummyScoreboard',
    VERSION_FROM => 'DummyScoreboard.pm',
);
