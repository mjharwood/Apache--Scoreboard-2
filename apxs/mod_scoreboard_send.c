#include "httpd.h"
#include "http_config.h"
#include "http_protocol.h"
#include "http_request.h"
#include "ap_mpm.h"
#include "scoreboard.h"
#include "send.c"

static void register_hooks(apr_pool_t *p)
{
    ap_hook_handler(scoreboard_send, NULL, NULL, APR_HOOK_MIDDLE);
}

module AP_MODULE_DECLARE_DATA scoreboard_send_module =
{
    STANDARD20_MODULE_STUFF,
    NULL,    /* per-directory config creator */
    NULL,     /* dir config merger */
    NULL, /* server config creator */
    NULL,  /* server config merger */
    NULL,                 /* command table */
    register_hooks,       /* set up other request processing hooks */
};

