#define REMOTE_SCOREBOARD_TYPE "application/x-httpd-scoreboard"

#ifndef Move
#define Move(s,d,n,t) (void)memmove((char*)(d),(char*)(s), (n) * sizeof(t)) 
#endif
#ifndef Copy
#define Copy(s,d,n,t) (void)memcpy((char*)(d),(char*)(s), (n) * sizeof(t))
#endif

/* use this macro when using with objects created by the pool, can't
 * mix memmove with pool allocation */
#define Copy_pool(p, s, n, t) apr_pmemdup(p, s, (n) * sizeof(t))

#define SIZE16 2

static void pack16(unsigned char *s, int p)
{
    short ashort = htons(p);
    Move(&ashort, s, SIZE16, unsigned char);
}

static unsigned short unpack16(unsigned char *s)
{
    unsigned short ashort;
    Copy(s, &ashort, SIZE16, char);
    return ntohs(ashort);
}

#define WRITE_BUFF(buf, size, r) \
    if (ap_rwrite(buf, size, r) < 0) { return APR_EGENERAL; }

static int scoreboard_send(request_rec *r)
{
    int i, psize, ssize, tsize;
    char buf[SIZE16*2];
    char *ptr = buf;

    for (i = 0; i < server_limit; i++) {
        if (!ap_scoreboard_image->parent[i].pid) {
            break;
        }
    }
    
    psize = i * sizeof(process_score);
    ssize = i * sizeof(worker_score);
    tsize = psize + ssize + sizeof(global_score) + sizeof(buf);

    pack16(ptr, psize);
    ptr += SIZE16;
    pack16(ptr, ssize);

    ap_set_content_length(r, tsize);
    r->content_type = REMOTE_SCOREBOARD_TYPE;
    
    if (!r->header_only) {
	WRITE_BUFF(&buf[0],                          sizeof(buf),          r);
	WRITE_BUFF(&ap_scoreboard_image->parent[0],  psize,                r);
	WRITE_BUFF(&ap_scoreboard_image->servers[0], ssize,                r);
	WRITE_BUFF(&ap_scoreboard_image->global,     sizeof(global_score), r);
    }

    return APR_SUCCESS;
}


