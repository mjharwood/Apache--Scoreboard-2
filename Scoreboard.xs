#define PERL_NO_GET_CONTEXT /* we want efficiency */
/* #include "xs/modperl_xs_typedefs.h" */
#include "mod_perl.h"
#include "modperl_xs_sv_convert.h"
#include "modperl_xs_typedefs.h"

#include "scoreboard.h"

/* scoreboard */
typedef struct {
    scoreboard *sb;
    apr_pool_t *pool;
} modperl_scoreboard_t;

typedef struct {
    worker_score record;
    int parent_idx;
    int worker_idx;
} modperl_worker_score_t;

typedef struct {
    process_score record;
    int idx;
    scoreboard *sb;
    apr_pool_t *pool;
} modperl_parent_score_t;

typedef modperl_scoreboard_t   *Apache__Scoreboard;
typedef modperl_worker_score_t *Apache__ScoreboardWorkerScore;
typedef modperl_parent_score_t *Apache__ScoreboardParentScore;

/* XXX: When documenting don't forget to add the new 'vhost' accessor */
/* and port accessor if it gets added (need to add it here too) */

int server_limit, thread_limit;

static char status_flags[SERVER_NUM_STATUS];

#define scoreboard_up_time(image) \
    (apr_uint32_t) apr_time_sec( \
        apr_time_now() - image->sb->global->restart_time);

#define parent_score_pid(mps)  mps->record.pid

#define worker_score_most_recent(mws) \
    (apr_uint32_t) apr_time_sec(apr_time_now() - mws->record.last_used);
        
#define worker_score_access_count(mws)    mws->record.access_count
#define worker_score_bytes_served(mws)    mws->record.bytes_served
#define worker_score_my_access_count(mws) mws->record.my_access_count
#define worker_score_my_bytes_served(mws) mws->record.my_bytes_served
#define worker_score_conn_bytes(mws)      mws->record.conn_bytes
#define worker_score_conn_count(mws)      mws->record.conn_count
#define worker_score_client(mws)          mws->record.client
#define worker_score_request(mws)         mws->record.request
#define worker_score_vhost(mws)           mws->record.vhost

/* a worker that have served/serves at least one request and isn't
 * dead yet */
#define LIVE_WORKER(ws) ws.access_count != 0 || \
    ws.status != SERVER_DEAD

/* a worker that does something at this very moment */
#define ACTIVE_WORKER(ws) ws.access_count != 0 || \
    (ws.status != SERVER_DEAD && ws.status != SERVER_READY)





static void status_flags_init(void)
{
    status_flags[SERVER_DEAD]           = '.';
    status_flags[SERVER_READY]          = '_';
    status_flags[SERVER_STARTING]       = 'S';
    status_flags[SERVER_BUSY_READ]      = 'R';
    status_flags[SERVER_BUSY_WRITE]     = 'W';
    status_flags[SERVER_BUSY_KEEPALIVE] = 'K';
    status_flags[SERVER_BUSY_LOG]       = 'L';
    status_flags[SERVER_BUSY_DNS]       = 'D';
    status_flags[SERVER_CLOSING]        = 'C';
    status_flags[SERVER_GRACEFUL]       = 'G';
    status_flags[SERVER_IDLE_KILL]      = 'I';
}

#include "apxs/send.c"

MODULE = Apache::Scoreboard   PACKAGE = Apache::Scoreboard   PREFIX = scoreboard_

BOOT:
{
    HV *stash;

    /* XXX: this must be performed only once and before other threads are spawned.
     * but not sure. could be that need to use local storage.
     *
     */
    status_flags_init();
    
    ap_mpm_query(AP_MPMQ_HARD_LIMIT_THREADS, &thread_limit);
    ap_mpm_query(AP_MPMQ_HARD_LIMIT_DAEMONS, &server_limit);

    stash = gv_stashpv("Apache::Const", TRUE);
    newCONSTSUB(stash, "SERVER_LIMIT", newSViv(server_limit));
    
    stash = gv_stashpv("Apache::Const", TRUE);
    newCONSTSUB(stash, "THREAD_LIMIT", newSViv(thread_limit));

    stash = gv_stashpv("Apache::Scoreboard", TRUE);
    newCONSTSUB(stash, "REMOTE_SCOREBOARD_TYPE",
                newSVpv(REMOTE_SCOREBOARD_TYPE, 0));
}

int
scoreboard_send(r)
    Apache::RequestRec r



SV *
freeze(image)
    Apache::Scoreboard image

    PREINIT:
    int i, psize, ssize, tsize;
    char buf[SIZE16*2];
    char *dptr, *data, *ptr = buf;
    scoreboard *sb;

    CODE:
    sb = image->sb;
    
    for (i = 0; i < server_limit; i++) {
        if (!sb->parent[i].pid) {
            break;
        }
    }
    
    psize = i * sizeof(process_score);
    ssize = i * sizeof(worker_score);
    tsize = psize + ssize + sizeof(global_score) + sizeof(buf);
    /* fprintf(stderr, "sizes %d, %d, %d, %d, %d, %d\n",
       i, psize, ssize, sizeof(global_score) , sizeof(buf), tsize); */

    data = (char *)apr_palloc(image->pool, tsize);
    
    pack16(ptr, psize);
    ptr += SIZE16;
    pack16(ptr, ssize);
    
    /* fill the data buffer with the data we want to freeze */
    dptr = data;
    Move(buf,             dptr, sizeof(buf),          char);
    dptr += sizeof(buf);
    Move(&sb->parent[0],  dptr, psize,                char);
    dptr += psize;
    Move(&sb->servers[0], dptr, ssize,                char);
    dptr += ssize;
    Move(&sb->global,     dptr, sizeof(global_score), char);

    /* an equivalent C function can return 'data', in case of XS it'll
     * try to convert char *data to PV, using strlen(), which will
     * lose data, since it won't continue past the first \0
     * char. Therefore in this case we explicitly return SV* and using
     * newSVpvn(data, tsize) to tell the exact size */
    RETVAL = newSVpvn(data, tsize);

    OUTPUT:
    RETVAL

Apache::Scoreboard
thaw(CLASS, pool, packet)
    SV *CLASS
    APR::Pool pool
    SV *packet

    PREINIT:
    modperl_scoreboard_t *image;
    scoreboard *sb;
    int psize, ssize;
    char *ptr;

    CODE:
    if (!(SvOK(packet) && SvCUR(packet) > (SIZE16*2))) {
	XSRETURN_UNDEF;
    }

    CLASS = CLASS; /* avoid warnings */
 
    image = (modperl_scoreboard_t *)apr_palloc(pool, sizeof(*image));
    sb          =     (scoreboard *)apr_palloc(pool, sizeof(scoreboard));
    sb->parent  =  (process_score *)apr_palloc(pool, sizeof(process_score *));
    sb->servers =  (worker_score **)apr_palloc(pool, server_limit * sizeof(worker_score));
    sb->global  =   (global_score *)apr_palloc(pool, sizeof(global_score *));
    
    ptr = SvPVX(packet);
    psize = unpack16(ptr);
    ptr += SIZE16;
    ssize = unpack16(ptr);
    ptr += SIZE16;

    Move(ptr, &sb->parent[0], psize, char);
    ptr += psize;
    Move(ptr, &sb->servers[0], ssize, char);
    ptr += ssize;
    Move(ptr, &sb->global, sizeof(global_score), char);

    image->pool = pool;
    image->sb   = sb;

    RETVAL = image;

    OUTPUT:
    RETVAL

Apache::Scoreboard
image(CLASS, pool)
    SV *CLASS
    APR::Pool pool
    
    CODE:
    RETVAL = (modperl_scoreboard_t *)apr_palloc(pool, sizeof(*RETVAL));
    
    if (ap_exists_scoreboard_image()) {
        RETVAL->sb = ap_scoreboard_image;
        RETVAL->pool = pool;
    }
    else {
        Perl_croak(aTHX_ "ap_scoreboard_image doesn't exist");
    }

    CLASS = CLASS; /* avoid warnings */

    OUTPUT:
    RETVAL

Apache::ScoreboardParentScore
parent_score(self, idx=0)
    Apache::Scoreboard self
    int idx

    CODE:
    if (self->sb->parent[idx].pid) {
        RETVAL = (modperl_parent_score_t *)apr_pcalloc(self->pool, (sizeof(*RETVAL)));
        RETVAL->record = self->sb->parent[idx];
        RETVAL->idx    = idx;
        RETVAL->sb     = self->sb;
        RETVAL->pool   = self->pool;
    }
    else {
	XSRETURN_UNDEF;
    }

    OUTPUT:
    RETVAL

Apache::ScoreboardWorkerScore
worker_score(self, parent_idx, worker_idx)
    Apache::Scoreboard self
    int parent_idx
    int worker_idx

    CODE:
    RETVAL = (modperl_worker_score_t *)apr_pcalloc(self->pool, (sizeof(*RETVAL)));

    RETVAL->record = self->sb->servers[parent_idx][worker_idx];
    RETVAL->parent_idx = parent_idx;
    RETVAL->worker_idx = worker_idx;
    
    OUTPUT:
    RETVAL

SV *
pids(self)
    Apache::Scoreboard self

    PREINIT:
    AV *av = newAV();
    int i;
    scoreboard *sb;

    CODE:
    sb = self->sb;
    for (i = 0; i < server_limit; i++) {
        if (!(sb->parent[i].pid)) {
            break;
        }
        /* fprintf(stderr, "pids: server %d: pid %d\n",
           i, (int)(sb->parent[i].pid)); */
        av_push(av, newSViv(sb->parent[i].pid));
    }
        
    RETVAL = newRV_noinc((SV*)av);

    OUTPUT:
    RETVAL

# XXX: need to move pid_t => apr_proc_t and work with pid->pid as in
# find_child_by_pid from scoreboard.c

int
parent_idx_by_pid(self, pid)   
    Apache::Scoreboard self
    pid_t pid

    PREINIT:
    int i;
    scoreboard *sb;

    CODE:
    sb = self->sb;
    RETVAL = -1;

    for (i = 0; i < server_limit; i++) {
        if (sb->parent[i].pid == pid) {
            RETVAL = i;
            break;
        }
    }

    OUTPUT:
    RETVAL

SV *
thread_numbers(self, parent_idx)
    Apache::Scoreboard self
    int parent_idx

    PREINIT:
    AV *av = newAV();
    int i;
    scoreboard *sb;

    CODE:
    sb = self->sb;

    for (i = 0; i < thread_limit; ++i) {
        /* fprintf(stderr, "thread_num: server %d, thread %d pid %d\n",
           i, sb->servers[parent_idx][i].thread_num,
           (int)(sb->parent[parent_idx].pid)); */
        
        av_push(av, newSViv(sb->servers[parent_idx][i].thread_num));
    }

    RETVAL = newRV_noinc((SV*)av);

    OUTPUT:
    RETVAL

apr_uint32_t
scoreboard_up_time(self)
    Apache::Scoreboard self

MODULE = Apache::Scoreboard PACKAGE = Apache::ScoreboardParentScore PREFIX = parent_score_
    
Apache::ScoreboardParentScore
next(self)
    Apache::ScoreboardParentScore self

    PREINIT:
    int next_idx;
    
    CODE:
    next_idx = self->idx + 1;

    if (self->sb->parent[next_idx].pid) {
        RETVAL = (modperl_parent_score_t *)apr_pcalloc(self->pool, sizeof(*RETVAL));
        RETVAL->record = self->sb->parent[next_idx];
        RETVAL->idx    = next_idx;
        RETVAL->sb     = self->sb;
        RETVAL->pool   = self->pool;
    }
    else {
	XSRETURN_UNDEF;
    }

    OUTPUT:
    RETVAL

Apache::ScoreboardWorkerScore
worker_score(self)
    Apache::ScoreboardParentScore self

    CODE:
    RETVAL = (modperl_worker_score_t *)apr_pcalloc(self->pool, sizeof(*RETVAL));
    RETVAL->record     = self->sb->servers[self->idx][0];
    RETVAL->parent_idx = self->idx;
    RETVAL->worker_idx = 0;

    OUTPUT:
    RETVAL
    
Apache::ScoreboardWorkerScore
next_worker_score(self, mws)
    Apache::ScoreboardParentScore self
    Apache::ScoreboardWorkerScore mws

    PREINIT:
    int next_idx;
    
    CODE:
    next_idx = mws->worker_idx + 1;
    if (next_idx < thread_limit) {
        RETVAL = (modperl_worker_score_t *)apr_pcalloc(self->pool, sizeof(*RETVAL));
        RETVAL->record     = self->sb->servers[mws->parent_idx][next_idx];
        RETVAL->parent_idx = mws->parent_idx;
        RETVAL->worker_idx = next_idx;
    }
    else {
	XSRETURN_UNDEF;
    }

    OUTPUT:
    RETVAL
    
    
Apache::ScoreboardWorkerScore
next_live_worker_score(self, mws)
    Apache::ScoreboardParentScore self
    Apache::ScoreboardWorkerScore mws

    PREINIT:
    int next_idx;
    int found = 0;
    
    CODE:
    next_idx = mws->worker_idx;

    while (++next_idx < thread_limit) {
        if (LIVE_WORKER(self->sb->servers[mws->parent_idx][next_idx])) {
            RETVAL = (modperl_worker_score_t *)apr_pcalloc(self->pool, sizeof(*RETVAL));
            RETVAL->record     = self->sb->servers[mws->parent_idx][next_idx];
            RETVAL->parent_idx = mws->parent_idx;
            RETVAL->worker_idx = next_idx;
            found++;
            break;
        }
    }

    if (!found) {
	XSRETURN_UNDEF;
    }

    OUTPUT:
    RETVAL
    


Apache::ScoreboardWorkerScore
next_active_worker_score(self, mws)
    Apache::ScoreboardParentScore self
    Apache::ScoreboardWorkerScore mws

    PREINIT:
    int next_idx;
    int found = 0;

    CODE:
    next_idx = mws->worker_idx;
    while (++next_idx < thread_limit) {
        if (ACTIVE_WORKER(self->sb->servers[mws->parent_idx][next_idx])) {
            RETVAL = (modperl_worker_score_t *)apr_pcalloc(self->pool, sizeof(*RETVAL));
            RETVAL->record     = self->sb->servers[mws->parent_idx][next_idx];
            RETVAL->parent_idx = mws->parent_idx;
            RETVAL->worker_idx = next_idx;
            found++;
            break;
        }
    }

    if (!found) {
	XSRETURN_UNDEF;
    }

    OUTPUT:
    RETVAL

pid_t
parent_score_pid(self)
    Apache::ScoreboardParentScore self
    
MODULE = Apache::Scoreboard PACKAGE = Apache::ScoreboardWorkerScore PREFIX = worker_score_

void
times(self)
    Apache::ScoreboardWorkerScore self

    PPCODE:
    if (GIMME == G_ARRAY) {
	/* same return values as CORE::times() */
	EXTEND(sp, 4);
	PUSHs(sv_2mortal(newSViv(self->record.times.tms_utime)));
	PUSHs(sv_2mortal(newSViv(self->record.times.tms_stime)));
	PUSHs(sv_2mortal(newSViv(self->record.times.tms_cutime)));
	PUSHs(sv_2mortal(newSViv(self->record.times.tms_cstime)));
    }
    else {
#ifdef _SC_CLK_TCK
	float tick = sysconf(_SC_CLK_TCK);
#else
	float tick = HZ;
#endif
	if (self->record.access_count) {
	    /* cpu %, same value mod_status displays */
	      float RETVAL = (self->record.times.tms_utime +
			      self->record.times.tms_stime +
			      self->record.times.tms_cutime +
			      self->record.times.tms_cstime);
	    XPUSHs(sv_2mortal(newSVnv((double)RETVAL/tick)));
	}
	else {
            
	    XPUSHs(sv_2mortal(newSViv((0))));
	}
    }


void
start_time(self)
    Apache::ScoreboardWorkerScore self

    ALIAS:
    stop_time = 1

    PREINIT:
    apr_time_t tp;

    PPCODE:
    ix = ix; /* warnings */
    tp = (XSANY.any_i32 == 0) ? 
         self->record.start_time : self->record.stop_time;

    /* fprintf(stderr, "start_time: %5" APR_TIME_T_FMT "\n", tp); */

    /* do the same as Time::HiRes::gettimeofday */
    if (GIMME == G_ARRAY) {
	EXTEND(sp, 2);
	PUSHs(sv_2mortal(newSViv(apr_time_sec(tp))));
	PUSHs(sv_2mortal(newSViv(apr_time_sec(tp) - apr_time_usec(tp))));
    } 
    else {
	EXTEND(sp, 1);
	PUSHs(sv_2mortal(newSVnv(apr_time_sec(tp))));
    }

long
req_time(self)
    Apache::ScoreboardWorkerScore self

    CODE:
    if (self->record.start_time == 0L) {
	RETVAL = 0L;
    }
    else {
	RETVAL = (long)
            ((self->record.stop_time - self->record.start_time) / 1000);
    }
    if (RETVAL < 0L || !self->record.access_count) {
	RETVAL = 0L;
    }

    OUTPUT:
    RETVAL

SV *
worker_score_status(self)
    Apache::ScoreboardWorkerScore self

    CODE:
    RETVAL = newSV(0);
    sv_setnv(RETVAL, (double)self->record.status);
    sv_setpvf(RETVAL, "%c", status_flags[self->record.status]);
    SvNOK_on(RETVAL); /* dual-var */ 

    OUTPUT:
    RETVAL



unsigned long
worker_score_access_count(self)
    Apache::ScoreboardWorkerScore self

unsigned long
worker_score_bytes_served(self)
    Apache::ScoreboardWorkerScore self

unsigned long
worker_score_my_access_count(self)
    Apache::ScoreboardWorkerScore self

unsigned long
worker_score_my_bytes_served(self)
    Apache::ScoreboardWorkerScore self

unsigned long
worker_score_conn_bytes(self)
    Apache::ScoreboardWorkerScore self

unsigned short
worker_score_conn_count(self)
    Apache::ScoreboardWorkerScore self

char *
worker_score_client(self)
    Apache::ScoreboardWorkerScore self

char *
worker_score_request(self)
    Apache::ScoreboardWorkerScore self

char *
worker_score_vhost(self)
    Apache::ScoreboardWorkerScore self

apr_uint32_t
worker_score_most_recent(self)
    Apache::ScoreboardWorkerScore self
