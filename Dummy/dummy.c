#include "httpd.h"
#include "scoreboard.h"

scoreboard *ap_scoreboard_image = NULL;

void ap_sync_scoreboard_image(void)
{
}

int ap_exists_scoreboard_image(void)
{
    return 0;
}
