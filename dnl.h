#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define NAME_TAG_NONE 0 // did not match any list
#define NAME_TAG_GFW 1 // hit the gfwlist
#define NAME_TAG_CHN 2 // hit the chnlist

/* initialize domain-name-list from file */
size_t dnl_init(const char *filename, bool is_gfwlist);

/* get name tag by dnl match */
uint8_t get_name_tag(const char *dname, bool is_gfwlist_first);
