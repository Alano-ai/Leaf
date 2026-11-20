/* SPDX-License-Identifier: GPL-3.0-only */

#include "LeafKindle.h"
#include <libxml/HTMLparser.h>
#include <libxml/tree.h>
#include <limits.h>
#include <string.h>

#ifdef USE_ENCRYPTION
#error "Leaf only supports unprotected books"
#endif

static const size_t input_limit = 64 * 1000 * 1000;
static const size_t text_limit = 32 * 1024 * 1024;
static const size_t font_limit = 16 * 1024 * 1024;

static uint16_t read_u16(const uint8_t *bytes) {
    return ((uint16_t)bytes[0] << 8) | bytes[1];
}

static uint32_t read_u32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static bool has_bounded_records(const uint8_t *bytes, size_t size) {
    if (size < 86 || memcmp(bytes + 60, "BOOKMOBI", 8) != 0) return false;
    const size_t records = read_u16(bytes + 76);
    const size_t directory_end = 78 + records * 8;
    if (records == 0 || directory_end >= size) return false;

    // libmobi allocates one buffer for each difference between adjacent offsets.
    size_t previous = directory_end;
    for (size_t record = 0; record < records; record++) {
        const size_t offset = read_u32(bytes + 78 + record * 8);
        if (offset < previous || offset >= size) return false;
        previous = offset;
    }
    return true;
}

static bool has_bounded_fonts(const MOBIData *book) {
    const size_t first_resource = mobi_get_first_resource_record(book);
    const MOBIPdbRecord *record = first_resource == MOBI_NOTSET
        ? book->rec : mobi_get_record_by_seqnumber(book, first_resource);
    size_t remaining = font_limit;
    for (; record; record = record->next) {
        if (record->size < 8 || memcmp(record->data, "FONT", 4) != 0) continue;
        const size_t decoded_size = read_u32(record->data + 4);
        if (decoded_size > remaining) return false;
        remaining -= decoded_size;
    }
    return true;
}

static bool has_fixed_layout(const MOBIData *book) {
    const MOBIExthHeader *layout = mobi_get_exthrecord_by_tag(book, EXTH_FIXEDLAYOUT);
    if (!layout || !layout->data) return false;
    const uint8_t *value = layout->data;
    if (layout->size == 1) return value[0] == 1 || value[0] == '1';
    if (layout->size == 4) return memcmp(value, "true", 4) == 0 || read_u32(value) == 1;
    return layout->size == 5 && value[4] == 0 && memcmp(value, "true", 4) == 0;
}

MOBIData *leaf_kindle_load(const uint8_t *bytes, size_t size, int *status) {
    *status = LEAF_KINDLE_INVALID;
    if (size > input_limit) {
        *status = LEAF_KINDLE_LIMIT;
        return NULL;
    }
    if (!bytes || !has_bounded_records(bytes, size)) return NULL;

    // The stream is read-only. libmobi copies input records during this call.
    FILE *stream = fmemopen((void *)bytes, size, "rb");
    if (!stream) return NULL;
    MOBIData *book = mobi_init();
    if (!book) {
        fclose(stream);
        return NULL;
    }
    const MOBI_RET result = mobi_load_file(book, stream);
    fclose(stream);
    if (result == MOBI_FILE_ENCRYPTED) {
        *status = LEAF_KINDLE_PROTECTED;
    } else if (result == MOBI_SUCCESS && book->rh) {
        if (book->rh->encryption_type != MOBI_ENCRYPTION_NONE ||
            (book->next && book->next->rh && book->next->rh->encryption_type != MOBI_ENCRYPTION_NONE)) {
            *status = LEAF_KINDLE_PROTECTED;
        } else if (mobi_is_replica(book) || has_fixed_layout(book)) {
            *status = LEAF_KINDLE_UNSUPPORTED;
        } else if (mobi_exists_mobiheader(book)) {
            const size_t text_size = mobi_get_text_maxsize(book);
            if (text_size != MOBI_NOTSET && text_size > 0) {
                if (text_size > text_limit || !has_bounded_fonts(book)) {
                    *status = LEAF_KINDLE_LIMIT;
                } else {
                    *status = 0;
                    return book;
                }
            }
        }
    }
    mobi_free(book);
    return NULL;
}

LeafKindleHTML *leaf_kindle_parse_html(const uint8_t *bytes, size_t size) {
    if (size == 0 || size > text_limit || size > INT_MAX) return NULL;
    const int options = HTML_PARSE_NODEFDTD | HTML_PARSE_NONET | HTML_PARSE_NOERROR |
                        HTML_PARSE_NOWARNING | HTML_PARSE_COMPACT;
    return (LeafKindleHTML *)htmlReadMemory((const char *)bytes, (int)size, NULL, "UTF-8", options);
}

void leaf_kindle_free_html(LeafKindleHTML *document) {
    xmlFreeDoc((xmlDocPtr)document);
}

const LeafKindleNode *leaf_kindle_html_body(const LeafKindleHTML *document) {
    const xmlNode *root = xmlDocGetRootElement((const xmlDoc *)document);
    for (const xmlNode *child = root ? root->children : NULL; child; child = child->next) {
        if (child->type == XML_ELEMENT_NODE && xmlStrEqual(child->name, BAD_CAST "body")) {
            return (const LeafKindleNode *)child;
        }
    }
    return NULL;
}

const LeafKindleNode *leaf_kindle_html_first_child(const LeafKindleNode *node) {
    return (const LeafKindleNode *)((const xmlNode *)node)->children;
}

const LeafKindleNode *leaf_kindle_html_next(const LeafKindleNode *node) {
    return (const LeafKindleNode *)((const xmlNode *)node)->next;
}

const char *leaf_kindle_html_tag(const LeafKindleNode *node) {
    const xmlNode *xml = (const xmlNode *)node;
    return xml->type == XML_ELEMENT_NODE ? (const char *)xml->name : NULL;
}

const char *leaf_kindle_html_text(const LeafKindleNode *node) {
    const xmlNode *xml = (const xmlNode *)node;
    return xml->type == XML_TEXT_NODE || xml->type == XML_CDATA_SECTION_NODE
        ? (const char *)xml->content : NULL;
}

char *leaf_kindle_html_attribute(const LeafKindleNode *node, const char *name) {
    return (char *)xmlGetNoNsProp((const xmlNode *)node, BAD_CAST name);
}

void leaf_kindle_free_attribute(char *value) {
    xmlFree(value);
}
