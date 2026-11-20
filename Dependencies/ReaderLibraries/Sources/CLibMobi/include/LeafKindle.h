/* SPDX-License-Identifier: GPL-3.0-only */

#ifndef LEAF_KINDLE_H
#define LEAF_KINDLE_H

#include <stdint.h>
#include <stddef.h>
#include "mobi.h"

enum {
    LEAF_KINDLE_INVALID = 1,
    LEAF_KINDLE_PROTECTED,
    LEAF_KINDLE_UNSUPPORTED,
    LEAF_KINDLE_LIMIT
};

/* The returned book owns its records and is released with mobi_free. */
MOBIData *leaf_kindle_load(const uint8_t *bytes, size_t size, int *status);

typedef struct LeafKindleHTML LeafKindleHTML;
typedef struct LeafKindleNode LeafKindleNode;

LeafKindleHTML *leaf_kindle_parse_html(const uint8_t *bytes, size_t size);
void leaf_kindle_free_html(LeafKindleHTML *document);
const LeafKindleNode *leaf_kindle_html_body(const LeafKindleHTML *document);
const LeafKindleNode *leaf_kindle_html_first_child(const LeafKindleNode *node);
const LeafKindleNode *leaf_kindle_html_next(const LeafKindleNode *node);
const char *leaf_kindle_html_tag(const LeafKindleNode *node);
const char *leaf_kindle_html_text(const LeafKindleNode *node);
char *leaf_kindle_html_attribute(const LeafKindleNode *node, const char *name);
void leaf_kindle_free_attribute(char *value);

#endif
