/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdbool.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
#include "mobi.h"

static bool protected_book(const MOBIData *book) {
    return mobi_is_encrypted(book) || (book->next && mobi_is_encrypted(book->next));
}

struct Parts {
    unsigned chapters;
    unsigned images;
    unsigned fonts;
    size_t markup_bytes;
};

static struct Parts count_parts(const MOBIRawml *raw) {
    struct Parts parts = {0};
    for (const MOBIPart *part = raw->markup; part; part = part->next) {
        parts.chapters++;
        parts.markup_bytes += part->size;
    }
    for (const MOBIPart *part = raw->resources; part; part = part->next) {
        switch (part->type) {
            case T_JPG:
            case T_PNG:
            case T_GIF: parts.images++; break;
            case T_TTF:
            case T_OTF: parts.fonts++; break;
            default: break;
        }
    }
    return parts;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: kindle-probe local-file\n");
        return 2;
    }
    struct stat file;
    if (stat(argv[1], &file) != 0 || !S_ISREG(file.st_mode) || file.st_size > 64000000) {
        fprintf(stderr, "Choose a regular file up to 64 MB.\n");
        return 2;
    }
    double start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6;
    MOBIData *book = mobi_init();
    if (!book) return 2;
    MOBI_RET result = mobi_load_filename(book, argv[1]);
    if (result == MOBI_FILE_ENCRYPTED || (result == MOBI_SUCCESS && protected_book(book))) {
        fprintf(stderr, "Protected MOBI/KF8 is unsupported.\n");
        mobi_free(book);
        return 3;
    }
    if (result != MOBI_SUCCESS || !mobi_exists_mobiheader(book)) {
        fprintf(stderr, "Invalid MOBI/KF8.\n");
        mobi_free(book);
        return 2;
    }
    MOBIRawml *raw = mobi_init_rawml(book);
    if (!raw) {
        mobi_free(book);
        return 2;
    }
    result = mobi_parse_rawml_opt(raw, book, true, false, true);
    struct Parts parts = count_parts(raw);
    if (result == MOBI_SUCCESS && parts.markup_bytes > 0) {
        double time_ms = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6 - start;
        printf("version=%zu markup_parts=%u markup_bytes=%zu images=%u fonts=%u toc_entries=%zu prepare_ms=%.2f\n",
               mobi_get_fileversion(book), parts.chapters, parts.markup_bytes,
               parts.images, parts.fonts, raw->ncx ? raw->ncx->entries_count : 0, time_ms);
    } else {
        fprintf(stderr, "MOBI/KF8 markup could not be parsed.\n");
        result = MOBI_DATA_CORRUPT;
    }
    mobi_free_rawml(raw);
    mobi_free(book);
    return result == MOBI_SUCCESS ? 0 : 2;
}
