In order to be able to run the test suite you have to tell Makefile.PL,
where the server can be found:

e.g.:

  perl Makefile.PL -apxs /home/stas/httpd/prefork/bin/apxs

Notice that mod_perl that is used in the test must be built with
exactly the same perl binary. If not you may have problems with
unresolved symbols at the server startup.
