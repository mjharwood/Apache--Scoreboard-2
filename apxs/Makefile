APXS = apxs

.SUFFIXES: .c .o .so

MODULES = mod_scoreboard_send.so

all: $(MODULES)

.c.so: $*.c
	$(APXS) -c $(DEF) $(INC) $(LIB) $*.c

install: all
	@for i in $(MODULES); do \
		$(APXS) -i -a $$i; \
	done

clean:
	rm -f *.o *.so
