#include "httpd.h"  
#include "http_config.h"  
#include "http_request.h"  
#include "http_protocol.h"  
#include "http_core.h"  
#include "http_main.h" 
#include "http_log.h"  

#include "scoreboard.h"

#include "send.c"

static handler_rec handlers[] =
{
    {"scoreboard-send-handler", scoreboard_send},
    {NULL}
};

module MODULE_VAR_EXPORT scoreboard_send_module = {
    STANDARD_MODULE_STUFF, 
    NULL,                  /* module initializer                  */
    NULL,                  /* create per-dir    config structures */
    NULL,                  /* merge  per-dir    config structures */
    NULL,                  /* create per-server config structures */
    NULL,                  /* merge  per-server config structures */
    NULL,                  /* table of config file commands       */
    handlers,              /* [#8] MIME-typed-dispatched handlers */
    NULL,                  /* [#1] URI to filename translation    */
    NULL,                  /* [#4] validate user id from request  */
    NULL,                  /* [#5] check if the user is ok _here_ */
    NULL,                  /* [#3] check access by host address   */
    NULL,                  /* [#6] determine MIME type            */
    NULL,                  /* [#7] pre-run fixups                 */
    NULL,                  /* [#9] log a transaction              */
    NULL,                  /* [#2] header parser                  */
    NULL,                  /* child_init                          */
    NULL,                  /* child_exit                          */
    NULL                   /* [#0] post read-request              */
};

