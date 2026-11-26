/* NSXMLParser (event-driven) and the NSXMLNode tree (NSXMLNode,
 * NSXMLElement, NSXMLDocument), as documented, over one XML 1.0 reader
 * written here: the declaration and its encoding, comments, processing
 * instructions, CDATA, DOCTYPE with internal entity declarations, character
 * and entity references, namespaces, and the well-formedness errors under
 * NSXMLParserErrorDomain with libxml2's numbering (which NSXMLParser
 * reports). External entities and DTD validation are not supported.
 * nodesForXPath:error: evaluates XPath 1.0 location paths: the child,
 * descendant(-or-self), self, parent, attribute, ancestor and sibling axes,
 * name, *, node(), text() and comment() tests, and predicates with
 * positions, comparisons, and/or/not, last(), position(), count(),
 * contains(), starts-with(), string(), name(), local-name() and
 * normalize-space(). */
#import "FoundationInternal.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

NSString *const NSXMLParserErrorDomain = @"NSXMLParserErrorDomain";

/* ---- the reader ------------------------------------------------------------------------- */

@protocol BNXMLSink
- (void)bn_startDocument;
- (void)bn_endDocument;
- (void)bn_doctype:(NSString *)name publicID:(NSString *)publicID systemID:(NSString *)systemID;
/* attrs: [qname, local, prefix, uri, value] each; nsDecls: [prefix, uri] each */
- (void)bn_startElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
             attributes:(NSArray<NSArray *> *)attrs namespaces:(NSArray<NSArray *> *)nsDecls;
- (void)bn_endElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
           namespaces:(NSArray<NSArray *> *)nsDecls;
- (void)bn_characters:(NSString *)text;
- (void)bn_cdata:(NSString *)text;
- (void)bn_comment:(NSString *)text;
- (void)bn_processingInstruction:(NSString *)target data:(NSString *)data;
- (BOOL)bn_stopped;
@end

typedef struct {
    const char *s, *p, *end;
    id<BNXMLSink> sink;
    int errcode;
    NSString *errmsg;
    const char *errat;
    NSMutableDictionary<NSString *, NSString *> *entities;
    NSMutableArray<NSMutableDictionary<NSString *, NSString *> *> *nsStack;
    BOOL namespaces;      /* resolve prefixes */
    NSString *encoding, *version;
    int standalone;       /* -1 unset */
} Reader;

#define XML_NS @"http://www.w3.org/XML/1998/namespace"

static BOOL rfail(Reader *r, int code, NSString *msg) {
    if (!r->errcode) {
        r->errcode = code;
        r->errmsg = msg;
        r->errat = r->p;
    }
    return NO;
}
static NSString *str(const char *a, size_t n) {
    return [[NSString alloc] initWithBytes:a length:n encoding:NSUTF8StringEncoding] ?: @"";
}
static BOOL is_ws(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
static void skip_ws(Reader *r) { while (r->p < r->end && is_ws(*r->p)) r->p++; }
static BOOL starts(Reader *r, const char *lit) {
    size_t n = strlen(lit);
    return (size_t)(r->end - r->p) >= n && memcmp(r->p, lit, n) == 0;
}
static BOOL name_start(unsigned char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':' || c >= 0x80; }
static BOOL name_char(unsigned char c) { return name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'; }
static NSString *read_name(Reader *r) {
    const char *a = r->p;
    if (r->p >= r->end || !name_start((unsigned char)*r->p)) return nil;
    while (r->p < r->end && name_char((unsigned char)*r->p)) r->p++;
    return str(a, (size_t)(r->p - a));
}
static void append_cp(NSMutableString *out, uint32_t cp) {
    if (cp < 0x10000) {
        unichar c = (unichar)cp;
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    } else {
        cp -= 0x10000;
        unichar pair[2] = {(unichar)(0xd800 + (cp >> 10)), (unichar)(0xdc00 + (cp & 0x3ff))};
        [out appendString:[NSString stringWithCharacters:pair length:2]];
    }
}
/* &...; at r->p (after '&'); appends its text */
static BOOL read_reference(Reader *r, NSMutableString *out) {
    if (r->p < r->end && *r->p == '#') {
        r->p++;
        uint32_t v = 0;
        int digits = 0, hex = r->p < r->end && *r->p == 'x';
        if (hex) r->p++;
        while (r->p < r->end && *r->p != ';') {
            char c = *r->p;
            int d = c >= '0' && c <= '9' ? c - '0' : hex && c >= 'a' && c <= 'f' ? c - 'a' + 10 : hex && c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
            if (d < 0) return rfail(r, hex ? 6 : 7, hex ? @"invalid hexadecimal character reference" : @"invalid decimal character reference");
            v = v * (hex ? 16 : 10) + (uint32_t)d;
            if (v > 0x10ffff) return rfail(r, 8, @"character reference out of range");
            digits++;
            r->p++;
        }
        if (r->p >= r->end) return rfail(r, 10, @"character reference at end of input");
        if (!digits || v == 0 || (v >= 0xd800 && v < 0xe000)) return rfail(r, 8, @"invalid character reference");
        r->p++;
        append_cp(out, v);
        return YES;
    }
    NSString *name = read_name(r);
    if (!name) return rfail(r, 68, @"entity name expected");
    if (r->p >= r->end || *r->p != ';') return rfail(r, 23, @"';' expected after entity reference");
    r->p++;
    static NSDictionary *predefined;
    if (!predefined) predefined = @{@"lt" : @"<", @"gt" : @">", @"amp" : @"&", @"apos" : @"'", @"quot" : @"\""};
    NSString *v = predefined[name] ?: r->entities[name];
    if (!v) return rfail(r, 26, [NSString stringWithFormat:@"Entity '%@' not defined", name]);
    [out appendString:v];
    return YES;
}
/* text up to (not including) stop chars, line ends normalized, references decoded */
static void append_bytes(NSMutableString *out, const char *a, const char *b) {
    /* \r\n and \r become \n */
    const char *seg = a;
    for (const char *q = a; q < b; q++) {
        if (*q == '\r') {
            [out appendString:str(seg, (size_t)(q - seg))];
            [out appendString:@"\n"];
            if (q + 1 < b && q[1] == '\n') q++;
            seg = q + 1;
        }
    }
    if (seg < b) [out appendString:str(seg, (size_t)(b - seg))];
}
static NSString *read_quoted(Reader *r, BOOL attribute) {
    if (r->p >= r->end || (*r->p != '"' && *r->p != '\'')) {
        rfail(r, attribute ? 39 : 43, attribute ? @"attribute value expected" : @"quoted literal expected");
        return nil;
    }
    char q = *r->p++;
    NSMutableString *out = [NSMutableString string];
    const char *seg = r->p;
    while (r->p < r->end && *r->p != q) {
        char c = *r->p;
        if (attribute && c == '<') { rfail(r, 38, @"'<' in attribute value"); return nil; }
        if (attribute && c == '&') {
            append_bytes(out, seg, r->p);
            r->p++;
            if (!read_reference(r, out)) return nil;
            seg = r->p;
            continue;
        }
        r->p++;
    }
    if (r->p >= r->end) { rfail(r, attribute ? 40 : 44, attribute ? @"attribute value not finished" : @"literal not finished"); return nil; }
    append_bytes(out, seg, r->p);
    r->p++;
    if (attribute) { /* attribute-value normalization: whitespace characters become spaces */
        for (NSUInteger i = 0; i < out.length; i++) {
            unichar c = [out characterAtIndex:i];
            if (c == '\t' || c == '\n') [out replaceCharactersInRange:NSMakeRange(i, 1) withString:@" "];
        }
    }
    return out;
}

static BOOL read_comment(Reader *r, BOOL report) {
    r->p += 4; /* <!-- */
    const char *a = r->p;
    while (r->p + 2 < r->end && !(r->p[0] == '-' && r->p[1] == '-' && r->p[2] == '>')) r->p++;
    if (r->p + 2 >= r->end) return rfail(r, 45, @"Comment not terminated");
    NSString *text = str(a, (size_t)(r->p - a));
    r->p += 3;
    if (report) [r->sink bn_comment:text];
    return YES;
}
static BOOL read_pi(Reader *r, BOOL report) {
    r->p += 2; /* <? */
    NSString *target = read_name(r);
    if (!target) return rfail(r, 46, @"processing instruction target expected");
    if ([target caseInsensitiveCompare:@"xml"] == NSOrderedSame) return rfail(r, 64, @"XML declaration allowed only at the start of the document");
    skip_ws(r);
    const char *a = r->p;
    while (r->p + 1 < r->end && !(r->p[0] == '?' && r->p[1] == '>')) r->p++;
    if (r->p + 1 >= r->end) return rfail(r, 47, @"processing instruction not terminated");
    NSString *data = str(a, (size_t)(r->p - a));
    r->p += 2;
    if (report) [r->sink bn_processingInstruction:target data:data];
    return YES;
}
static BOOL read_xmldecl(Reader *r) {
    r->p += 5; /* <?xml */
    for (;;) {
        skip_ws(r);
        if (starts(r, "?>")) { r->p += 2; return YES; }
        NSString *name = read_name(r);
        if (!name) return rfail(r, 57, @"malformed XML declaration");
        skip_ws(r);
        if (r->p >= r->end || *r->p != '=') return rfail(r, 75, @"'=' expected in XML declaration");
        r->p++;
        skip_ws(r);
        NSString *v = read_quoted(r, NO);
        if (!v) return NO;
        if ([name isEqual:@"version"]) r->version = v;
        else if ([name isEqual:@"encoding"]) r->encoding = v;
        else if ([name isEqual:@"standalone"]) r->standalone = [v isEqual:@"yes"];
    }
}
static BOOL read_doctype(Reader *r) {
    r->p += 9; /* <!DOCTYPE */
    skip_ws(r);
    NSString *name = read_name(r), *publicID = nil, *systemID = nil;
    if (!name) return rfail(r, 68, @"DOCTYPE name expected");
    skip_ws(r);
    if (starts(r, "SYSTEM")) {
        r->p += 6;
        skip_ws(r);
        if (!(systemID = read_quoted(r, NO))) return NO;
    } else if (starts(r, "PUBLIC")) {
        r->p += 6;
        skip_ws(r);
        if (!(publicID = read_quoted(r, NO))) return NO;
        skip_ws(r);
        if (r->p < r->end && (*r->p == '"' || *r->p == '\'') && !(systemID = read_quoted(r, NO))) return NO;
    }
    skip_ws(r);
    if (r->p < r->end && *r->p == '[') {
        r->p++;
        for (;;) {
            skip_ws(r);
            if (r->p >= r->end) return rfail(r, 61, @"DOCTYPE internal subset not finished");
            if (*r->p == ']') { r->p++; break; }
            if (starts(r, "<!--")) { if (!read_comment(r, NO)) return NO; continue; }
            if (starts(r, "<?")) { if (!read_pi(r, NO)) return NO; continue; }
            if (starts(r, "<!ENTITY")) {
                r->p += 8;
                skip_ws(r);
                BOOL parameter = r->p < r->end && *r->p == '%';
                if (parameter) { r->p++; skip_ws(r); }
                NSString *ename = read_name(r);
                if (!ename) return rfail(r, 68, @"entity name expected");
                skip_ws(r);
                if (r->p < r->end && (*r->p == '"' || *r->p == '\'')) {
                    /* the value's character references are expanded now */
                    NSString *raw = read_quoted(r, NO);
                    if (!raw) return NO;
                    if (!parameter && !r->entities[ename]) {
                        NSMutableString *v = [NSMutableString string];
                        NSData *bytes = [raw dataUsingEncoding:NSUTF8StringEncoding];
                        Reader sub = *r;
                        sub.s = sub.p = bytes.bytes;
                        sub.end = sub.p + bytes.length;
                        const char *seg = sub.p;
                        while (sub.p < sub.end) {
                            if (*sub.p == '&' && sub.p + 1 < sub.end && sub.p[1] == '#') {
                                append_bytes(v, seg, sub.p);
                                sub.p++;
                                if (!read_reference(&sub, v)) return rfail(r, sub.errcode, sub.errmsg);
                                seg = sub.p;
                            } else sub.p++;
                        }
                        append_bytes(v, seg, sub.p);
                        r->entities[ename] = v;
                    }
                }
                /* external entities (SYSTEM/PUBLIC) are skipped, as with external loading off */
            }
            /* any other declaration: skip to its '>' outside quotes */
            char q = 0;
            while (r->p < r->end) {
                char c = *r->p++;
                if (q) { if (c == q) q = 0; }
                else if (c == '"' || c == '\'') q = c;
                else if (c == '>') break;
            }
        }
        skip_ws(r);
    }
    if (r->p >= r->end || *r->p != '>') return rfail(r, 61, @"DOCTYPE not finished");
    r->p++;
    [r->sink bn_doctype:name publicID:publicID systemID:systemID];
    return YES;
}

static NSString *lookup_ns(Reader *r, NSString *prefix) {
    if ([prefix isEqual:@"xml"]) return XML_NS;
    for (NSInteger i = (NSInteger)r->nsStack.count - 1; i >= 0; i--) {
        NSString *u = r->nsStack[(NSUInteger)i][prefix];
        if (u) return u.length || prefix.length == 0 ? u : nil;
    }
    return nil;
}
static void split_qname(NSString *q, NSString **prefix, NSString **local) {
    NSRange c = [q rangeOfString:@":"];
    if (c.location == NSNotFound || c.location == 0 || c.location + 1 == q.length) {
        *prefix = nil;
        *local = q;
    } else {
        *prefix = [q substringToIndex:c.location];
        *local = [q substringFromIndex:c.location + 1];
    }
}

static BOOL read_element(Reader *r, int depth);
static BOOL read_content(Reader *r, NSString *qname, int depth) {
    NSMutableString *text = nil;
    const char *seg = r->p;
#define FLUSH_TEXT()                                                    \
    do {                                                                \
        if (seg < r->p) {                                               \
            if (!text) text = [NSMutableString string];                 \
            append_bytes(text, seg, r->p);                              \
        }                                                               \
        if (text.length) [r->sink bn_characters:text];                  \
        text = nil;                                                     \
        if ([r->sink bn_stopped]) return NO;                            \
    } while (0)
    for (;;) {
        if (r->p >= r->end) {
            return rfail(r, 5, [NSString stringWithFormat:@"Premature end of data in tag %@", qname]);
        }
        char c = *r->p;
        if (c == '&') {
            if (!text) text = [NSMutableString string];
            append_bytes(text, seg, r->p);
            r->p++;
            if (!read_reference(r, text)) return NO;
            seg = r->p;
            continue;
        }
        if (c != '<') {
            if (c == ']' && starts(r, "]]>")) return rfail(r, 62, @"Sequence ']]>' not allowed in content");
            r->p++;
            continue;
        }
        FLUSH_TEXT();
        if (starts(r, "</")) {
            r->p += 2;
            NSString *end = read_name(r);
            if (!end) return rfail(r, 74, @"end tag name expected");
            if (![end isEqual:qname])
                return rfail(r, 76, [NSString stringWithFormat:@"Opening and ending tag mismatch: %@ and %@", qname, end]);
            skip_ws(r);
            if (r->p >= r->end || *r->p != '>') return rfail(r, 73, @"'>' expected");
            r->p++;
            return YES;
        }
        if (starts(r, "<!--")) {
            if (!read_comment(r, YES)) return NO;
        } else if (starts(r, "<![CDATA[")) {
            r->p += 9;
            const char *a = r->p;
            while (r->p + 2 < r->end && !(r->p[0] == ']' && r->p[1] == ']' && r->p[2] == '>')) r->p++;
            if (r->p + 2 >= r->end) return rfail(r, 63, @"CDATA section not finished");
            NSMutableString *cd = [NSMutableString string];
            append_bytes(cd, a, r->p);
            r->p += 3;
            [r->sink bn_cdata:cd];
        } else if (starts(r, "<?")) {
            if (!read_pi(r, YES)) return NO;
        } else if (starts(r, "<!")) {
            return rfail(r, 68, @"markup declaration not allowed in content");
        } else {
            if (!read_element(r, depth + 1)) return NO;
        }
        if ([r->sink bn_stopped]) return NO;
        seg = r->p;
    }
#undef FLUSH_TEXT
}

static BOOL read_element(Reader *r, int depth) {
    if (depth > 4000) return rfail(r, 1, @"elements nested too deeply");
    r->p++; /* < */
    NSString *qname = read_name(r);
    if (!qname) return rfail(r, 68, @"StartTag: invalid element name");
    NSMutableArray<NSArray *> *raw = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    BOOL empty = NO;
    for (;;) {
        BOOL hadSpace = r->p < r->end && is_ws(*r->p);
        skip_ws(r);
        if (r->p >= r->end) return rfail(r, 5, [NSString stringWithFormat:@"Couldn't find end of Start Tag %@", qname]);
        if (*r->p == '>') { r->p++; break; }
        if (starts(r, "/>")) { r->p += 2; empty = YES; break; }
        if (!hadSpace) return rfail(r, 65, @"attributes construct error");
        NSString *an = read_name(r);
        if (!an) return rfail(r, 73, [NSString stringWithFormat:@"Couldn't find end of Start Tag %@", qname]);
        skip_ws(r);
        if (r->p >= r->end || *r->p != '=') return rfail(r, 41, [NSString stringWithFormat:@"Specification mandates value for attribute %@", an]);
        r->p++;
        skip_ws(r);
        NSString *v = read_quoted(r, YES);
        if (!v) return NO;
        if ([seen containsObject:an]) return rfail(r, 42, [NSString stringWithFormat:@"Attribute %@ redefined", an]);
        [seen addObject:an];
        [raw addObject:@[ an, v ]];
    }
    /* namespace declarations on this element */
    NSMutableDictionary *scope = [NSMutableDictionary dictionary];
    NSMutableArray<NSArray *> *decls = [NSMutableArray array];
    for (NSArray *a in raw) {
        NSString *n = a[0];
        if ([n isEqual:@"xmlns"]) { scope[@""] = a[1]; [decls addObject:@[ @"", a[1] ]]; }
        else if ([n hasPrefix:@"xmlns:"]) {
            NSString *p = [n substringFromIndex:6];
            scope[p] = a[1];
            [decls addObject:@[ p, a[1] ]];
        }
    }
    [r->nsStack addObject:scope];
    NSString *prefix, *local;
    split_qname(qname, &prefix, &local);
    NSString *uri = lookup_ns(r, prefix ?: @"");
    NSMutableArray<NSArray *> *attrs = [NSMutableArray array];
    for (NSArray *a in raw) {
        NSString *an = a[0], *ap, *al;
        BOOL isDecl = [an isEqual:@"xmlns"] || [an hasPrefix:@"xmlns:"];
        if (isDecl && r->namespaces) continue; /* reported as mappings instead */
        split_qname(an, &ap, &al);
        NSString *au = ap && !isDecl ? lookup_ns(r, ap) : nil;
        [attrs addObject:@[ an, al, ap ?: @"", au ?: @"", a[1] ]];
    }
    [r->sink bn_startElement:qname local:local prefix:prefix ?: @"" uri:uri ?: @"" attributes:attrs namespaces:decls];
    if ([r->sink bn_stopped]) return NO;
    if (!empty && !read_content(r, qname, depth)) return NO;
    [r->sink bn_endElement:qname local:local prefix:prefix ?: @"" uri:uri ?: @"" namespaces:decls];
    [r->nsStack removeLastObject];
    return ![r->sink bn_stopped];
}

/* A whole document. Returns NO (and fills r->err*) on an error. */
static BOOL read_document(Reader *r) {
    [r->sink bn_startDocument];
    if ([r->sink bn_stopped]) return NO;
    skip_ws(r);
    if (r->p >= r->end) return rfail(r, 4, @"Document is empty");
    BOOL root = NO;
    for (;;) {
        skip_ws(r);
        if (r->p >= r->end) break;
        if (*r->p != '<') return rfail(r, root ? 5 : 4, root ? @"Extra content at the end of the document" : @"Start tag expected, '<' not found");
        if (starts(r, "<?xml") && r->p + 5 < r->end && (is_ws(r->p[5]) || r->p[5] == '?'))
            return rfail(r, 64, @"XML declaration allowed only at the start of the document");
        if (starts(r, "<!--")) { if (!read_comment(r, YES)) return NO; }
        else if (starts(r, "<?")) { if (!read_pi(r, YES)) return NO; }
        else if (starts(r, "<!DOCTYPE")) {
            if (root) return rfail(r, 5, @"Extra content at the end of the document");
            if (!read_doctype(r)) return NO;
        } else if (starts(r, "<!")) return rfail(r, 3, @"markup declaration not allowed here");
        else {
            if (root) return rfail(r, 5, @"Extra content at the end of the document");
            if (!read_element(r, 0)) return NO;
            root = YES;
        }
        if ([r->sink bn_stopped]) return NO;
    }
    if (!root) return rfail(r, 5, @"Start tag expected, '<' not found");
    [r->sink bn_endDocument];
    return YES;
}

/* The document's bytes as UTF-8, by BOM or declared encoding; also the
 * encoding name found. */
static NSData *utf8_bytes(NSData *data, NSString **found) {
    const unsigned char *b = data.bytes;
    NSUInteger n = data.length;
    NSStringEncoding enc = 0;
    if (n >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) return [data subdataWithRange:NSMakeRange(3, n - 3)];
    if (n >= 2 && b[0] == 0xff && b[1] == 0xfe) enc = NSUTF16LittleEndianStringEncoding;
    else if (n >= 2 && b[0] == 0xfe && b[1] == 0xff) enc = NSUTF16BigEndianStringEncoding;
    else if (n >= 4 && b[0] == '<' && b[1] == 0 && b[2] == '?' && b[3] == 0) enc = NSUTF16LittleEndianStringEncoding;
    else if (n >= 4 && b[0] == 0 && b[1] == '<' && b[2] == 0 && b[3] == '?') enc = NSUTF16BigEndianStringEncoding;
    if (enc) {
        NSData *body = (b[0] == 0xff || b[0] == 0xfe) ? [data subdataWithRange:NSMakeRange(2, n - 2)] : data;
        NSString *s = [[NSString alloc] initWithData:body encoding:enc];
        if (found) *found = @"UTF-16";
        return [s dataUsingEncoding:NSUTF8StringEncoding];
    }
    /* a declared single-byte encoding */
    if (n >= 6 && memcmp(b, "<?xml", 5) == 0) {
        const unsigned char *e = memchr(b, '>', n < 200 ? n : 200);
        NSString *decl = e ? [[NSString alloc] initWithBytes:b length:(NSUInteger)(e - b) encoding:NSASCIIStringEncoding] : nil;
        NSRange r = [decl rangeOfString:@"encoding"];
        if (r.location != NSNotFound) {
            NSString *rest = [decl substringFromIndex:NSMaxRange(r)];
            NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\"'"];
            NSArray *parts = [rest componentsSeparatedByCharactersInSet:quotes];
            NSString *name = parts.count > 1 ? [parts[1] lowercaseString] : nil;
            NSStringEncoding single = 0;
            if ([name isEqual:@"iso-8859-1"] || [name isEqual:@"latin1"] || [name isEqual:@"iso_8859-1"]) single = NSISOLatin1StringEncoding;
            else if ([name isEqual:@"windows-1252"] || [name isEqual:@"cp1252"]) single = NSISOLatin1StringEncoding;
            else if ([name isEqual:@"us-ascii"] || [name isEqual:@"ascii"]) single = NSASCIIStringEncoding;
            if (single && single != NSASCIIStringEncoding) {
                NSString *s = [[NSString alloc] initWithData:data encoding:single];
                return [s dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }
    return data;
}

static void position_of(const char *s, const char *at, NSInteger *line, NSInteger *column) {
    NSInteger l = 1, c = 1;
    for (const char *q = s; q < at; q++) {
        if (*q == '\n') { l++; c = 1; }
        else if (((unsigned char)*q & 0xc0) != 0x80) c++;
    }
    *line = l;
    *column = c;
}

/* ---- NSXMLParser ------------------------------------------------------------------------------- */

@interface NSXMLParser () <BNXMLSink>
@end

@implementation NSXMLParser {
    NSData *_data;
    BOOL _aborted, _parsing;
    NSError *_error;
    Reader *_reader;
    NSInteger _line, _column;
}
@synthesize delegate = _delegate, shouldProcessNamespaces = _shouldProcessNamespaces,
            shouldReportNamespacePrefixes = _shouldReportNamespacePrefixes,
            shouldResolveExternalEntities = _shouldResolveExternalEntities,
            externalEntityResolvingPolicy = _externalEntityResolvingPolicy,
            allowedExternalEntityURLs = _allowedExternalEntityURLs;
- (instancetype)initWithData:(NSData *)data {
    if ((self = [super init])) {
        _data = [data copy] ?: [NSData data];
        _externalEntityResolvingPolicy = NSXMLParserResolveExternalEntitiesNever;
    }
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url {
    NSData *d = url.isFileURL ? [NSData dataWithContentsOfFile:url.path] : nil;
    if (!d) return nil;
    return [self initWithData:d];
}
- (instancetype)initWithStream:(NSInputStream *)stream {
    NSMutableData *d = [NSMutableData data];
    [stream open];
    uint8_t buf[16384];
    NSInteger n;
    while ((n = [stream read:buf maxLength:sizeof buf]) > 0) [d appendBytes:buf length:(NSUInteger)n];
    [stream close];
    return [self initWithData:d];
}
- (NSError *)parserError { return _error; }
- (NSString *)publicID { return nil; }
- (NSString *)systemID { return nil; }
- (NSInteger)lineNumber {
    if (_reader) position_of(_reader->s, _reader->p, &_line, &_column);
    return _line;
}
- (NSInteger)columnNumber {
    if (_reader) position_of(_reader->s, _reader->p, &_line, &_column);
    return _column;
}
- (void)abortParsing {
    if (!_parsing) return;
    _aborted = YES;
}

- (BOOL)parse {
    if (_parsing) return NO;
    _parsing = YES;
    _aborted = NO;
    _error = nil;
    NSString *enc = nil;
    NSData *bytes = utf8_bytes(_data, &enc);
    Reader r = {0};
    r.s = r.p = bytes.bytes;
    r.end = r.p + bytes.length;
    r.sink = self;
    r.entities = [NSMutableDictionary dictionary];
    r.nsStack = [NSMutableArray array];
    r.namespaces = _shouldProcessNamespaces;
    r.standalone = -1;
    if (starts(&r, "<?xml") && r.p + 5 < r.end && (is_ws(r.p[5]) || r.p[5] == '?') && !read_xmldecl(&r)) {
        /* fall through to the error report */
    }
    _reader = &r;
    BOOL ok = !r.errcode && read_document(&r);
    position_of(r.s, r.errat ?: r.p, &_line, &_column);
    _reader = NULL;
    if (_aborted) {
        _error = [NSError errorWithDomain:NSXMLParserErrorDomain code:NSXMLParserDelegateAbortedParseError userInfo:nil];
        ok = NO;
    } else if (!ok) {
        NSString *msg = r.errmsg ?: @"parse error";
        _error = [NSError errorWithDomain:NSXMLParserErrorDomain code:r.errcode ?: 1
                                 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:
                                     @"The operation couldn’t be completed. (NSXMLParserErrorDomain error %d.)", r.errcode ?: 1],
                                            @"NSXMLParserErrorMessage" : [msg stringByAppendingString:@"\n"],
                                            @"NSXMLParserErrorLineNumber" : @(_line),
                                            @"NSXMLParserErrorColumn" : @(_column)}];
        if ([_delegate respondsToSelector:@selector(parser:parseErrorOccurred:)]) [_delegate parser:self parseErrorOccurred:_error];
    }
    _parsing = NO;
    return ok;
}

/* sink */
- (BOOL)bn_stopped { return _aborted; }
- (void)bn_startDocument {
    if ([_delegate respondsToSelector:@selector(parserDidStartDocument:)]) [_delegate parserDidStartDocument:self];
}
- (void)bn_endDocument {
    if ([_delegate respondsToSelector:@selector(parserDidEndDocument:)]) [_delegate parserDidEndDocument:self];
}
- (void)bn_doctype:(NSString *)name publicID:(NSString *)publicID systemID:(NSString *)systemID {}
- (void)bn_startElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
             attributes:(NSArray<NSArray *> *)attrs namespaces:(NSArray<NSArray *> *)decls {
    if (_shouldReportNamespacePrefixes && [_delegate respondsToSelector:@selector(parser:didStartMappingPrefix:toURI:)])
        for (NSArray *d in decls) {
            [_delegate parser:self didStartMappingPrefix:d[0] toURI:d[1]];
            if (_aborted) return;
        }
    if (![_delegate respondsToSelector:@selector(parser:didStartElement:namespaceURI:qualifiedName:attributes:)]) return;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:attrs.count];
    for (NSArray *a in attrs) dict[a[0]] = a[4];
    if (_shouldProcessNamespaces)
        [_delegate parser:self didStartElement:local namespaceURI:uri qualifiedName:qname attributes:dict];
    else
        [_delegate parser:self didStartElement:qname namespaceURI:nil qualifiedName:nil attributes:dict];
}
- (void)bn_endElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
           namespaces:(NSArray<NSArray *> *)decls {
    if ([_delegate respondsToSelector:@selector(parser:didEndElement:namespaceURI:qualifiedName:)]) {
        if (_shouldProcessNamespaces) [_delegate parser:self didEndElement:local namespaceURI:uri qualifiedName:qname];
        else [_delegate parser:self didEndElement:qname namespaceURI:nil qualifiedName:nil];
    }
    if (_shouldReportNamespacePrefixes && [_delegate respondsToSelector:@selector(parser:didEndMappingPrefix:)])
        for (NSArray *d in decls) {
            if (_aborted) return;
            [_delegate parser:self didEndMappingPrefix:d[0]];
        }
}
- (void)bn_characters:(NSString *)text {
    if ([_delegate respondsToSelector:@selector(parser:foundCharacters:)]) [_delegate parser:self foundCharacters:text];
}
- (void)bn_cdata:(NSString *)text {
    if ([_delegate respondsToSelector:@selector(parser:foundCDATA:)])
        [_delegate parser:self foundCDATA:[text dataUsingEncoding:NSUTF8StringEncoding]];
    else if ([_delegate respondsToSelector:@selector(parser:foundCharacters:)])
        [_delegate parser:self foundCharacters:text];
}
- (void)bn_comment:(NSString *)text {
    if ([_delegate respondsToSelector:@selector(parser:foundComment:)]) [_delegate parser:self foundComment:text];
}
- (void)bn_processingInstruction:(NSString *)target data:(NSString *)data {
    if ([_delegate respondsToSelector:@selector(parser:foundProcessingInstructionWithTarget:data:)])
        [_delegate parser:self foundProcessingInstructionWithTarget:target data:data];
}
@end

/* ---- the node tree ------------------------------------------------------------------------- */

@interface NSXMLNode () {
  @public
    NSXMLNodeKind _kind;
    NSString *_name;
    NSString *_value;        /* text, comment, attribute, namespace, PI */
    NSString *_uri;
    NSMutableArray<NSXMLNode *> *_children;
    __weak NSXMLNode *_parent;
    NSUInteger _options;
    id _objectValue;
}
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options;
@end

@interface NSXMLElement () {
  @public
    NSMutableArray<NSXMLNode *> *_attributes;
    NSMutableArray<NSXMLNode *> *_namespaces;
}
@end

@interface NSXMLDocument () {
  @public
    NSString *_encoding, *_version, *_mime;
    BOOL _standalone;
    NSXMLDocumentContentKind _contentKind;
    NSXMLDTD *_dtd;
}
@end

static NSString *escape_text(NSString *s, BOOL attribute) {
    if (!s.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
        case '&': [out appendString:@"&amp;"]; break;
        case '<': [out appendString:@"&lt;"]; break;
        case '>': [out appendString:@"&gt;"]; break;
        case '"': [out appendString:attribute ? @"&quot;" : @"\""]; break;
        case '\r': [out appendString:@"&#xD;"]; break;
        case '\n': [out appendString:attribute ? @"&#xA;" : @"\n"]; break;
        case '\t': [out appendString:attribute ? @"&#x9;" : @"\t"]; break;
        default: [out appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }
    return out;
}

NSArray *bn_xpath(NSXMLNode *context, NSString *xpath, NSString **why);

@implementation NSXMLNode
- (instancetype)init { return [self initWithKind:NSXMLInvalidKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind { return [self initWithKind:kind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options {
    if ((self = [super init])) {
        _kind = kind;
        _options = options;
        if (kind == NSXMLElementKind && ![self isKindOfClass:[NSXMLElement class]]) return [[NSXMLElement alloc] initWithKind:kind options:options];
        if (kind == NSXMLDocumentKind && ![self isKindOfClass:[NSXMLDocument class]]) return [[NSXMLDocument alloc] initWithKind:kind options:options];
        if (kind == NSXMLElementKind || kind == NSXMLDocumentKind) _children = [NSMutableArray array];
    }
    return self;
}
+ (id)document { return [[NSXMLDocument alloc] initWithKind:NSXMLDocumentKind options:0]; }
+ (id)documentWithRootElement:(NSXMLElement *)element { return [[NSXMLDocument alloc] initWithRootElement:element]; }
+ (id)elementWithName:(NSString *)name { return [[NSXMLElement alloc] initWithName:name]; }
+ (id)elementWithName:(NSString *)name URI:(NSString *)URI { return [[NSXMLElement alloc] initWithName:name URI:URI]; }
+ (id)elementWithName:(NSString *)name stringValue:(NSString *)string { return [[NSXMLElement alloc] initWithName:name stringValue:string]; }
+ (id)elementWithName:(NSString *)name children:(NSArray<NSXMLNode *> *)children attributes:(NSArray<NSXMLNode *> *)attributes {
    NSXMLElement *e = [[NSXMLElement alloc] initWithName:name];
    e.children = children;
    e.attributes = attributes;
    return e;
}
+ (id)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue {
    NSXMLNode *n = [[NSXMLNode alloc] initWithKind:NSXMLAttributeKind];
    n->_name = [name copy];
    n->_value = [stringValue copy] ?: @"";
    return n;
}
+ (id)attributeWithName:(NSString *)name URI:(NSString *)URI stringValue:(NSString *)stringValue {
    NSXMLNode *n = [self attributeWithName:name stringValue:stringValue];
    n->_uri = [URI copy];
    return n;
}
+ (id)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue {
    NSXMLNode *n = [[NSXMLNode alloc] initWithKind:NSXMLNamespaceKind];
    n->_name = [name copy] ?: @"";
    n->_value = [stringValue copy] ?: @"";
    return n;
}
+ (id)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue {
    NSXMLNode *n = [[NSXMLNode alloc] initWithKind:NSXMLProcessingInstructionKind];
    n->_name = [name copy];
    n->_value = [stringValue copy] ?: @"";
    return n;
}
+ (id)commentWithStringValue:(NSString *)stringValue {
    NSXMLNode *n = [[NSXMLNode alloc] initWithKind:NSXMLCommentKind];
    n->_value = [stringValue copy] ?: @"";
    return n;
}
+ (id)textWithStringValue:(NSString *)stringValue {
    NSXMLNode *n = [[NSXMLNode alloc] initWithKind:NSXMLTextKind];
    n->_value = [stringValue copy] ?: @"";
    return n;
}
+ (NSString *)localNameForName:(NSString *)name {
    NSString *p, *l;
    split_qname(name, &p, &l);
    return l;
}
+ (NSString *)prefixForName:(NSString *)name {
    NSString *p, *l;
    split_qname(name, &p, &l);
    return p ?: @"";
}
+ (NSXMLNode *)predefinedNamespaceForPrefix:(NSString *)name {
    if ([name isEqual:@"xml"]) return [self namespaceWithName:@"xml" stringValue:XML_NS];
    if ([name isEqual:@"xs"]) return [self namespaceWithName:@"xs" stringValue:@"http://www.w3.org/2001/XMLSchema"];
    if ([name isEqual:@"xsi"]) return [self namespaceWithName:@"xsi" stringValue:@"http://www.w3.org/2001/XMLSchema-instance"];
    return nil;
}

- (NSXMLNodeKind)kind { return _kind; }
- (NSString *)name { return _kind == NSXMLTextKind || _kind == NSXMLCommentKind || _kind == NSXMLDocumentKind ? nil : _name; }
- (void)setName:(NSString *)name { _name = [name copy]; }
- (NSString *)localName { return _name ? [NSXMLNode localNameForName:_name] : nil; }
- (NSString *)prefix { return _name ? [NSXMLNode prefixForName:_name] : nil; }
- (NSString *)URI {
    if (_uri) return _uri;
    if (_kind == NSXMLElementKind || (_kind == NSXMLAttributeKind && self.prefix.length)) {
        /* resolve the prefix in scope */
        NSString *prefix = self.prefix ?: @"";
        NSXMLNode *e = _kind == NSXMLElementKind ? self : _parent;
        if ([prefix isEqual:@"xml"]) return XML_NS;
        for (; e; e = e->_parent)
            if (e->_kind == NSXMLElementKind)
                for (NSXMLNode *ns in ((NSXMLElement *)e)->_namespaces)
                    if ([ns->_name isEqual:prefix]) return ns->_value.length ? ns->_value : nil;
    }
    return nil;
}
- (void)setURI:(NSString *)URI { _uri = [URI copy]; }
- (NSUInteger)index {
    if (!_parent) return 0;
    NSUInteger i = [_parent->_children indexOfObjectIdenticalTo:self];
    return i == NSNotFound ? 0 : i;
}
- (NSUInteger)level {
    NSUInteger l = 0;
    for (NSXMLNode *p = _parent; p; p = p->_parent) l++;
    return l;
}
- (NSXMLDocument *)rootDocument {
    NSXMLNode *n = self;
    while (n->_parent) n = n->_parent;
    return n->_kind == NSXMLDocumentKind ? (NSXMLDocument *)n : nil;
}
- (NSXMLNode *)parent { return _parent; }
- (NSUInteger)childCount { return _children.count; }
- (NSArray<NSXMLNode *> *)children { return _children ? [_children copy] : nil; }
- (NSXMLNode *)childAtIndex:(NSUInteger)index { return index < _children.count ? _children[index] : nil; }
- (NSXMLNode *)previousSibling {
    if (!_parent || _kind == NSXMLAttributeKind || _kind == NSXMLNamespaceKind) return nil;
    NSUInteger i = [_parent->_children indexOfObjectIdenticalTo:self];
    return i != NSNotFound && i > 0 ? _parent->_children[i - 1] : nil;
}
- (NSXMLNode *)nextSibling {
    if (!_parent || _kind == NSXMLAttributeKind || _kind == NSXMLNamespaceKind) return nil;
    NSUInteger i = [_parent->_children indexOfObjectIdenticalTo:self];
    return i != NSNotFound && i + 1 < _parent->_children.count ? _parent->_children[i + 1] : nil;
}
- (NSXMLNode *)nextNode {
    if (_children.count) return _children[0];
    for (NSXMLNode *n = self; n; n = n->_parent) {
        NSXMLNode *s = n.nextSibling;
        if (s) return s;
    }
    return nil;
}
- (NSXMLNode *)previousNode {
    NSXMLNode *s = self.previousSibling;
    if (!s) return _parent;
    while (s->_children.count) s = s->_children.lastObject;
    return s;
}
- (void)detach {
    NSXMLNode *p = _parent;
    if (!p) return;
    if (_kind == NSXMLAttributeKind) [((NSXMLElement *)p)->_attributes removeObjectIdenticalTo:self];
    else if (_kind == NSXMLNamespaceKind) [((NSXMLElement *)p)->_namespaces removeObjectIdenticalTo:self];
    else [p->_children removeObjectIdenticalTo:self];
    _parent = nil;
}

- (NSString *)stringValue {
    switch (_kind) {
    case NSXMLElementKind: case NSXMLDocumentKind: {
        NSMutableString *s = [NSMutableString string];
        for (NSXMLNode *c in _children)
            if (c->_kind == NSXMLTextKind || c->_kind == NSXMLElementKind) [s appendString:c.stringValue];
        return s;
    }
    default: return _value ?: @"";
    }
}
- (void)setStringValue:(NSString *)string {
    if (_kind == NSXMLElementKind || _kind == NSXMLDocumentKind) {
        for (NSXMLNode *c in _children) c->_parent = nil;
        [_children removeAllObjects];
        if (string.length) {
            NSXMLNode *t = [NSXMLNode textWithStringValue:string];
            t->_parent = self;
            [_children addObject:t];
        }
    } else {
        _value = [string copy] ?: @"";
    }
}
- (void)setStringValue:(NSString *)string resolvingEntities:(BOOL)resolve { [self setStringValue:string]; }
- (id)objectValue { return _objectValue ?: self.stringValue; }
- (void)setObjectValue:(id)value {
    _objectValue = value;
    self.stringValue = [value description];
}

- (NSString *)XMLString { return [self XMLStringWithOptions:NSXMLNodeOptionsNone]; }
- (NSString *)_bn_xml:(NSUInteger)options indent:(NSUInteger)depth {
    BOOL pretty = (options & NSXMLNodePrettyPrint) != 0;
    switch (_kind) {
    case NSXMLTextKind:
        if (_options & NSXMLNodeIsCDATA) return [NSString stringWithFormat:@"<![CDATA[%@]]>", _value ?: @""];
        return (options & NSXMLNodeNeverEscapeContents) ? (_value ?: @"") : escape_text(_value, NO);
    case NSXMLCommentKind: return [NSString stringWithFormat:@"<!--%@-->", _value ?: @""];
    case NSXMLProcessingInstructionKind:
        return _value.length ? [NSString stringWithFormat:@"<?%@ %@?>", _name, _value] : [NSString stringWithFormat:@"<?%@?>", _name];
    case NSXMLAttributeKind: {
        BOOL single = (options & NSXMLNodeUseSingleQuotes) != 0;
        NSString *v = escape_text(_value, YES);
        return single ? [NSString stringWithFormat:@"%@='%@'", _name, [v stringByReplacingOccurrencesOfString:@"'" withString:@"&apos;"]]
                      : [NSString stringWithFormat:@"%@=\"%@\"", _name, v];
    }
    case NSXMLNamespaceKind: {
        NSString *n = _name.length ? [@"xmlns:" stringByAppendingString:_name] : @"xmlns";
        return [NSString stringWithFormat:@"%@=\"%@\"", n, escape_text(_value, YES)];
    }
    case NSXMLElementKind: {
        NSXMLElement *e = (NSXMLElement *)self;
        NSMutableString *s = [NSMutableString stringWithFormat:@"<%@", _name];
        for (NSXMLNode *ns in e->_namespaces) [s appendFormat:@" %@", [ns _bn_xml:options indent:0]];
        for (NSXMLNode *a in e->_attributes) [s appendFormat:@" %@", [a _bn_xml:options indent:0]];
        if (!_children.count) {
            BOOL compact = (options & NSXMLNodeCompactEmptyElement) || ((_options & NSXMLNodeCompactEmptyElement) && !(options & NSXMLNodeExpandEmptyElement));
            if (compact) [s appendString:@"/>"];
            else [s appendFormat:@"></%@>", _name];
            return s;
        }
        [s appendString:@">"];
        BOOL elementsOnly = pretty;
        for (NSXMLNode *c in _children)
            if (c->_kind == NSXMLTextKind) elementsOnly = NO;
        for (NSXMLNode *c in _children) {
            if (elementsOnly) [s appendFormat:@"\n%@", [@"" stringByPaddingToLength:(depth + 1) * 4 withString:@" " startingAtIndex:0]];
            [s appendString:[c _bn_xml:options indent:depth + 1]];
        }
        if (elementsOnly) [s appendFormat:@"\n%@", [@"" stringByPaddingToLength:depth * 4 withString:@" " startingAtIndex:0]];
        [s appendFormat:@"</%@>", _name];
        return s;
    }
    case NSXMLDocumentKind: {
        NSXMLDocument *d = (NSXMLDocument *)self;
        NSMutableString *s = [NSMutableString string];
        [s appendFormat:@"<?xml version=\"%@\"", d->_version ?: @"1.0"];
        if (d->_encoding) [s appendFormat:@" encoding=\"%@\"", d->_encoding];
        if (d->_standalone) [s appendString:@" standalone=\"yes\""];
        [s appendString:@"?>"];
        for (NSXMLNode *c in _children) {
            [s appendString:@"\n"];
            [s appendString:[c _bn_xml:options indent:0]];
        }
        return s;
    }
    default: return @"";
    }
}
- (NSString *)XMLStringWithOptions:(NSXMLNodeOptions)options { return [self _bn_xml:options indent:0]; }
- (NSString *)canonicalXMLStringPreservingComments:(BOOL)comments { return [self XMLStringWithOptions:NSXMLNodeCompactEmptyElement]; }
- (NSString *)description { return self.XMLString; }

- (NSString *)XPath {
    if (_kind == NSXMLDocumentKind) return @"/";
    if (!_parent) return nil;
    NSString *step;
    switch (_kind) {
    case NSXMLAttributeKind: step = [@"@" stringByAppendingString:_name]; break;
    case NSXMLTextKind: case NSXMLCommentKind: case NSXMLElementKind: case NSXMLProcessingInstructionKind: {
        NSString *test = _kind == NSXMLTextKind ? @"text()" : _kind == NSXMLCommentKind ? @"comment()" :
                         _kind == NSXMLProcessingInstructionKind ? @"processing-instruction()" : _name;
        NSUInteger pos = 0, count = 0;
        for (NSXMLNode *c in _parent->_children) {
            BOOL same = c->_kind == _kind && (_kind != NSXMLElementKind || [c->_name isEqual:_name]);
            if (same) {
                count++;
                if (c == self) pos = count;
            }
        }
        step = [NSString stringWithFormat:@"%@[%lu]", test, (unsigned long)pos];
        break;
    }
    default: return nil;
    }
    NSString *up = _parent.XPath;
    if ([up isEqual:@"/"]) return [@"/" stringByAppendingString:step];
    return up ? [NSString stringWithFormat:@"%@/%@", up, step] : step;
}
- (NSArray<__kindof NSXMLNode *> *)nodesForXPath:(NSString *)xpath error:(NSError **)error {
    NSString *why = nil;
    NSArray *r = bn_xpath(self, xpath, &why);
    if (!r && error)
        *error = [NSError errorWithDomain:NSXMLParserErrorDomain code:1
                                 userInfo:@{NSLocalizedDescriptionKey : why ?: @"invalid XPath", @"NSXMLXPathExpression" : xpath ?: @""}];
    return r;
}
- (NSArray *)objectsForXQuery:(NSString *)xquery error:(NSError **)error { return [self nodesForXPath:xquery error:error]; }
- (id)copyWithZone:(NSZone *)zone {
    NSXMLNode *n = [[[self class] alloc] initWithKind:_kind options:_options];
    n->_name = _name;
    n->_value = _value;
    n->_uri = _uri;
    n->_objectValue = _objectValue;
    for (NSXMLNode *c in _children) {
        NSXMLNode *cc = [c copy];
        cc->_parent = n;
        [n->_children addObject:cc];
    }
    return n;
}
- (BOOL)isEqual:(id)other { return self == other; }
- (NSUInteger)hash { return (NSUInteger)(__bridge void *)self >> 4; }
@end

static void adopt(NSXMLNode *parent, NSXMLNode *child) {
    if (child->_parent)
        [NSException raise:NSInternalInconsistencyException format:@"Cannot add a child that has a parent; detach or copy first"];
    child->_parent = parent;
}

@implementation NSXMLElement
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options {
    if ((self = [super initWithKind:NSXMLElementKind options:options])) {
        _attributes = [NSMutableArray array];
        _namespaces = [NSMutableArray array];
    }
    return self;
}
- (instancetype)initWithName:(NSString *)name { return [self initWithName:name URI:nil]; }
- (instancetype)initWithName:(NSString *)name URI:(NSString *)URI {
    if ((self = [self initWithKind:NSXMLElementKind options:0])) {
        _name = [name copy];
        _uri = [URI copy];
    }
    return self;
}
- (instancetype)initWithName:(NSString *)name stringValue:(NSString *)string {
    if ((self = [self initWithName:name])) self.stringValue = string;
    return self;
}
- (instancetype)initWithXMLString:(NSString *)string error:(NSError **)error {
    NSXMLDocument *d = [[NSXMLDocument alloc] initWithXMLString:string options:0 error:error];
    NSXMLElement *root = d.rootElement;
    if (!root) return nil;
    [root detach];
    return root;
}
- (NSArray<NSXMLElement *> *)elementsForName:(NSString *)name {
    NSMutableArray *out = [NSMutableArray array];
    NSString *uri = nil;
    NSString *prefix = [NSXMLNode prefixForName:name];
    if (prefix.length) uri = [self resolvePrefixForNamespace:prefix];
    for (NSXMLNode *c in _children) {
        if (c->_kind != NSXMLElementKind) continue;
        if ([c->_name isEqual:name] || (uri && [c.localName isEqual:[NSXMLNode localNameForName:name]] && [c.URI isEqual:uri]))
            [out addObject:c];
    }
    return out;
}
- (NSString *)resolvePrefixForNamespace:(NSString *)prefix {
    for (NSXMLNode *e = self; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind)
            for (NSXMLNode *ns in ((NSXMLElement *)e)->_namespaces)
                if ([ns->_name isEqual:prefix]) return ns->_value;
    return [prefix isEqual:@"xml"] ? XML_NS : nil;
}
- (NSArray<NSXMLElement *> *)elementsForLocalName:(NSString *)localName URI:(NSString *)URI {
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in _children)
        if (c->_kind == NSXMLElementKind && [c.localName isEqual:localName] && ((!URI.length && !c.URI.length) || [c.URI isEqual:URI]))
            [out addObject:c];
    return out;
}
- (NSArray<NSXMLNode *> *)attributes { return _attributes.count ? [_attributes copy] : nil; }
- (void)setAttributes:(NSArray<NSXMLNode *> *)attributes {
    for (NSXMLNode *a in _attributes) a->_parent = nil;
    [_attributes removeAllObjects];
    for (NSXMLNode *a in attributes) [self addAttribute:a];
}
- (void)setAttributesWithDictionary:(NSDictionary<NSString *, NSString *> *)attributes {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in attributes) [a addObject:[NSXMLNode attributeWithName:k stringValue:attributes[k]]];
    self.attributes = a;
}
- (void)setAttributesAsDictionary:(NSDictionary *)attributes { [self setAttributesWithDictionary:attributes]; }
- (void)addAttribute:(NSXMLNode *)attribute {
    if ([self attributeForName:attribute->_name]) return; /* an existing attribute wins, as documented */
    adopt(self, attribute);
    [_attributes addObject:attribute];
}
- (void)removeAttributeForName:(NSString *)name {
    NSXMLNode *a = [self attributeForName:name];
    if (a) {
        a->_parent = nil;
        [_attributes removeObjectIdenticalTo:a];
    }
}
- (NSXMLNode *)attributeForName:(NSString *)name {
    for (NSXMLNode *a in _attributes)
        if ([a->_name isEqual:name]) return a;
    return nil;
}
- (NSXMLNode *)attributeForLocalName:(NSString *)localName URI:(NSString *)URI {
    for (NSXMLNode *a in _attributes)
        if ([a.localName isEqual:localName] && ((!URI.length && !a.URI.length) || [a.URI isEqual:URI])) return a;
    return nil;
}
- (NSArray<NSXMLNode *> *)namespaces { return _namespaces.count ? [_namespaces copy] : nil; }
- (void)setNamespaces:(NSArray<NSXMLNode *> *)namespaces {
    for (NSXMLNode *n in _namespaces) n->_parent = nil;
    [_namespaces removeAllObjects];
    for (NSXMLNode *n in namespaces) [self addNamespace:n];
}
- (void)addNamespace:(NSXMLNode *)aNamespace {
    for (NSXMLNode *n in _namespaces)
        if ([n->_name isEqual:aNamespace->_name]) return;
    adopt(self, aNamespace);
    [_namespaces addObject:aNamespace];
}
- (void)removeNamespaceForPrefix:(NSString *)name {
    for (NSXMLNode *n in [_namespaces copy])
        if ([n->_name isEqual:name]) {
            n->_parent = nil;
            [_namespaces removeObjectIdenticalTo:n];
        }
}
- (NSXMLNode *)namespaceForPrefix:(NSString *)name {
    for (NSXMLNode *e = self; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind)
            for (NSXMLNode *n in ((NSXMLElement *)e)->_namespaces)
                if ([n->_name isEqual:name ?: @""]) return n;
    return [NSXMLNode predefinedNamespaceForPrefix:name];
}
- (NSXMLNode *)resolveNamespaceForName:(NSString *)name { return [self namespaceForPrefix:[NSXMLNode prefixForName:name]]; }
- (NSString *)resolvePrefixForNamespaceURI:(NSString *)namespaceURI {
    for (NSXMLNode *e = self; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind)
            for (NSXMLNode *n in ((NSXMLElement *)e)->_namespaces)
                if ([n->_value isEqual:namespaceURI]) return n->_name;
    return nil;
}
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index {
    adopt(self, child);
    [_children insertObject:child atIndex:index];
}
- (void)insertChildren:(NSArray<NSXMLNode *> *)children atIndex:(NSUInteger)index {
    for (NSXMLNode *c in children) [self insertChild:c atIndex:index++];
}
- (void)removeChildAtIndex:(NSUInteger)index {
    NSXMLNode *c = _children[index];
    c->_parent = nil;
    [_children removeObjectAtIndex:index];
}
- (void)setChildren:(NSArray<NSXMLNode *> *)children {
    for (NSXMLNode *c in _children) c->_parent = nil;
    [_children removeAllObjects];
    for (NSXMLNode *c in children) [self addChild:c];
}
- (void)addChild:(NSXMLNode *)child {
    adopt(self, child);
    [_children addObject:child];
}
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node {
    NSXMLNode *old = _children[index];
    adopt(self, node);
    old->_parent = nil;
    _children[index] = node;
}
- (void)normalizeAdjacentTextNodesPreservingCDATA:(BOOL)preserve {
    for (NSUInteger i = 0; i + 1 < _children.count;) {
        NSXMLNode *a = _children[i], *b = _children[i + 1];
        BOOL cdata = preserve && ((a->_options | b->_options) & NSXMLNodeIsCDATA);
        if (a->_kind == NSXMLTextKind && b->_kind == NSXMLTextKind && !cdata) {
            a->_value = [a->_value stringByAppendingString:b->_value];
            b->_parent = nil;
            [_children removeObjectAtIndex:i + 1];
        } else i++;
    }
    for (NSXMLNode *c in _children)
        if (c->_kind == NSXMLElementKind) [(NSXMLElement *)c normalizeAdjacentTextNodesPreservingCDATA:preserve];
}
- (id)copyWithZone:(NSZone *)zone {
    NSXMLElement *e = [super copyWithZone:zone];
    for (NSXMLNode *a in _attributes) [e addAttribute:[a copy]];
    for (NSXMLNode *n in _namespaces) [e addNamespace:[n copy]];
    return e;
}
@end

@implementation NSXMLDTD
@end

/* builds the tree from the reader's events */
@interface BNXMLTreeBuilder : NSObject <BNXMLSink> {
  @public
    NSXMLDocument *_doc;
    NSXMLNode *_current;
    NSUInteger _options;
}
@end
@implementation BNXMLTreeBuilder
- (BOOL)bn_stopped { return NO; }
- (void)bn_startDocument {}
- (void)bn_endDocument {}
- (void)bn_doctype:(NSString *)name publicID:(NSString *)publicID systemID:(NSString *)systemID {
    NSXMLDTD *dtd = [[NSXMLDTD alloc] initWithKind:NSXMLDTDKind options:0];
    dtd->_name = name;
    dtd.publicID = publicID;
    dtd.systemID = systemID;
    _doc->_dtd = dtd;
}
- (void)add:(NSXMLNode *)n {
    n->_parent = _current;
    [_current->_children addObject:n];
}
- (void)bn_startElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
             attributes:(NSArray<NSArray *> *)attrs namespaces:(NSArray<NSArray *> *)decls {
    NSXMLElement *e = [[NSXMLElement alloc] initWithName:qname];
    for (NSArray *d in decls) {
        NSXMLNode *ns = [NSXMLNode namespaceWithName:d[0] stringValue:d[1]];
        ns->_parent = e;
        [e->_namespaces addObject:ns];
    }
    for (NSArray *a in attrs) {
        NSXMLNode *at = [NSXMLNode attributeWithName:a[0] stringValue:a[4]];
        at->_parent = e;
        [e->_attributes addObject:at];
    }
    [self add:e];
    _current = e;
}
- (void)bn_endElement:(NSString *)qname local:(NSString *)local prefix:(NSString *)prefix uri:(NSString *)uri
           namespaces:(NSArray<NSArray *> *)decls {
    _current = _current->_parent;
}
- (void)bn_characters:(NSString *)text {
    if (_current == _doc) return;
    BOOL preserve = (_options & NSXMLNodePreserveWhitespace) != 0;
    if (!preserve && ![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return;
    NSXMLNode *last = _current->_children.lastObject;
    if (last && last->_kind == NSXMLTextKind && !(last->_options & NSXMLNodeIsCDATA)) {
        last->_value = [last->_value stringByAppendingString:text];
        return;
    }
    [self add:[NSXMLNode textWithStringValue:text]];
}
- (void)bn_cdata:(NSString *)text {
    NSXMLNode *t = [[NSXMLNode alloc] initWithKind:NSXMLTextKind options:(_options & NSXMLNodePreserveCDATA) ? NSXMLNodeIsCDATA : 0];
    t->_value = text;
    if (!(_options & NSXMLNodePreserveCDATA)) {
        NSXMLNode *last = _current->_children.lastObject;
        if (last && last->_kind == NSXMLTextKind && !(last->_options & NSXMLNodeIsCDATA)) {
            last->_value = [last->_value stringByAppendingString:text];
            return;
        }
    }
    [self add:t];
}
- (void)bn_comment:(NSString *)text { [self add:[NSXMLNode commentWithStringValue:text]]; }
- (void)bn_processingInstruction:(NSString *)target data:(NSString *)data {
    [self add:[NSXMLNode processingInstructionWithName:target stringValue:data]];
}
@end

@implementation NSXMLDocument
- (instancetype)init { return [self initWithKind:NSXMLDocumentKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options {
    if ((self = [super initWithKind:NSXMLDocumentKind options:options])) {
        _children = [NSMutableArray array];
        _version = @"1.0";
    }
    return self;
}
- (instancetype)initWithXMLString:(NSString *)string options:(NSXMLNodeOptions)mask error:(NSError **)error {
    return [self initWithData:[string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] options:mask error:error];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSXMLNodeOptions)mask error:(NSError **)error {
    NSData *d = url.isFileURL ? [NSData dataWithContentsOfFile:url.path] : nil;
    if (!d) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:@{NSURLErrorKey : url ?: (id)[NSNull null]}];
        return nil;
    }
    return [self initWithData:d options:mask error:error];
}
- (instancetype)initWithData:(NSData *)data options:(NSXMLNodeOptions)mask error:(NSError **)error {
    if (!(self = [self initWithKind:NSXMLDocumentKind options:mask])) return nil;
    NSString *enc = nil;
    NSData *bytes = utf8_bytes(data ?: [NSData data], &enc);
    BNXMLTreeBuilder *b = [BNXMLTreeBuilder new];
    b->_doc = self;
    b->_current = self;
    b->_options = mask;
    Reader r = {0};
    r.s = r.p = bytes.bytes;
    r.end = r.p + bytes.length;
    r.sink = b;
    r.entities = [NSMutableDictionary dictionary];
    r.nsStack = [NSMutableArray array];
    r.namespaces = YES;
    r.standalone = -1;
    BOOL ok = YES;
    if (starts(&r, "<?xml") && r.p + 5 < r.end && (is_ws(r.p[5]) || r.p[5] == '?')) ok = read_xmldecl(&r);
    if (ok) ok = read_document(&r);
    if (!ok) {
        NSInteger line, column;
        position_of(r.s, r.errat ?: r.p, &line, &column);
        if (error)
            *error = [NSError errorWithDomain:NSXMLParserErrorDomain code:r.errcode ?: 1
                                     userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ at line %ld",
                                                                                r.errmsg ?: @"parse error", (long)line]}];
        return nil;
    }
    _version = r.version ?: @"1.0";
    _encoding = r.encoding ?: enc;
    _standalone = r.standalone == 1;
    return self;
}
- (instancetype)initWithRootElement:(NSXMLElement *)element {
    if ((self = [self initWithKind:NSXMLDocumentKind options:0]) && element) [self setRootElement:element];
    return self;
}
+ (Class)replacementClassForClass:(Class)cls { return cls; }
- (NSXMLElement *)rootElement {
    for (NSXMLNode *c in _children)
        if (c->_kind == NSXMLElementKind) return (NSXMLElement *)c;
    return nil;
}
- (void)setRootElement:(NSXMLElement *)root {
    for (NSXMLNode *c in _children) c->_parent = nil;
    [_children removeAllObjects];
    if (root) [self addChild:root];
}
- (NSString *)characterEncoding { return _encoding; }
- (void)setCharacterEncoding:(NSString *)e { _encoding = [e copy]; }
- (NSString *)version { return _version; }
- (void)setVersion:(NSString *)v { _version = [v copy]; }
- (BOOL)isStandalone { return _standalone; }
- (void)setStandalone:(BOOL)s { _standalone = s; }
- (NSXMLDocumentContentKind)documentContentKind { return _contentKind; }
- (void)setDocumentContentKind:(NSXMLDocumentContentKind)k { _contentKind = k; }
- (NSString *)MIMEType { return _mime; }
- (void)setMIMEType:(NSString *)m { _mime = [m copy]; }
- (NSXMLDTD *)DTD { return _dtd; }
- (void)setDTD:(NSXMLDTD *)dtd { _dtd = dtd; }
- (void)addChild:(NSXMLNode *)child {
    adopt(self, child);
    [_children addObject:child];
}
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index {
    adopt(self, child);
    [_children insertObject:child atIndex:index];
}
- (void)insertChildren:(NSArray<NSXMLNode *> *)children atIndex:(NSUInteger)index {
    for (NSXMLNode *c in children) [self insertChild:c atIndex:index++];
}
- (void)removeChildAtIndex:(NSUInteger)index {
    _children[index]->_parent = nil;
    [_children removeObjectAtIndex:index];
}
- (void)setChildren:(NSArray<NSXMLNode *> *)children {
    for (NSXMLNode *c in _children) c->_parent = nil;
    [_children removeAllObjects];
    for (NSXMLNode *c in children) [self addChild:c];
}
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node {
    adopt(self, node);
    _children[index]->_parent = nil;
    _children[index] = node;
}
- (NSData *)XMLData { return [self XMLDataWithOptions:NSXMLNodeOptionsNone]; }
- (NSData *)XMLDataWithOptions:(NSXMLNodeOptions)options {
    return [[self XMLStringWithOptions:options] dataUsingEncoding:NSUTF8StringEncoding];
}
- (BOOL)validateAndReturnError:(NSError **)error { return YES; }
- (id)copyWithZone:(NSZone *)zone {
    NSXMLDocument *d = [super copyWithZone:zone];
    d->_encoding = _encoding;
    d->_version = _version;
    d->_standalone = _standalone;
    d->_contentKind = _contentKind;
    d->_mime = _mime;
    return d;
}
@end

/* ---- XPath ------------------------------------------------------------------------------------- */

typedef struct {
    NSString *s;
    NSUInteger i;
    NSString *error;
    NSXMLNode *context; /* for namespace prefixes */
} XP;

typedef enum { V_NODES, V_STRING, V_NUMBER, V_BOOL } VKind;
@interface BNXPValue : NSObject {
  @public
    VKind kind;
    NSArray<NSXMLNode *> *nodes;
    NSString *string;
    double number;
    BOOL boolean;
}
@end
@implementation BNXPValue
@end
static BNXPValue *v_nodes(NSArray *n) { BNXPValue *v = [BNXPValue new]; v->kind = V_NODES; v->nodes = n; return v; }
static BNXPValue *v_string(NSString *s) { BNXPValue *v = [BNXPValue new]; v->kind = V_STRING; v->string = s ?: @""; return v; }
static BNXPValue *v_number(double d) { BNXPValue *v = [BNXPValue new]; v->kind = V_NUMBER; v->number = d; return v; }
static BNXPValue *v_bool(BOOL b) { BNXPValue *v = [BNXPValue new]; v->kind = V_BOOL; v->boolean = b; return v; }
static NSString *as_string(BNXPValue *v) {
    switch (v->kind) {
    case V_NODES: return v->nodes.count ? v->nodes[0].stringValue : @"";
    case V_STRING: return v->string;
    case V_NUMBER: return v->number == (long long)v->number ? [NSString stringWithFormat:@"%lld", (long long)v->number] : [NSString stringWithFormat:@"%g", v->number];
    case V_BOOL: return v->boolean ? @"true" : @"false";
    }
    return @"";
}
static double as_number(BNXPValue *v) {
    switch (v->kind) {
    case V_NUMBER: return v->number;
    case V_BOOL: return v->boolean;
    default: {
        NSString *s = [as_string(v) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!s.length) return NAN;
        char *end;
        double d = strtod(s.UTF8String, &end);
        return *end ? NAN : d;
    }
    }
}
static BOOL as_bool(BNXPValue *v) {
    switch (v->kind) {
    case V_NODES: return v->nodes.count > 0;
    case V_STRING: return v->string.length > 0;
    case V_NUMBER: return v->number != 0 && !isnan(v->number);
    case V_BOOL: return v->boolean;
    }
    return NO;
}

static void xp_ws(XP *x) {
    while (x->i < x->s.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[x->s characterAtIndex:x->i]]) x->i++;
}
static unichar xp_peek(XP *x) { xp_ws(x); return x->i < x->s.length ? [x->s characterAtIndex:x->i] : 0; }
static BOOL xp_eat(XP *x, NSString *tok) {
    xp_ws(x);
    if ([x->s length] - x->i >= tok.length && [[x->s substringWithRange:NSMakeRange(x->i, tok.length)] isEqual:tok]) {
        x->i += tok.length;
        return YES;
    }
    return NO;
}
static NSString *xp_name(XP *x) {
    xp_ws(x);
    NSUInteger a = x->i;
    while (x->i < x->s.length) {
        unichar c = [x->s characterAtIndex:x->i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80 || (x->i > a && ((c >= '0' && c <= '9') || c == '-' || c == '.'));
        if (c == ':' && x->i > a && x->i + 1 < x->s.length && [x->s characterAtIndex:x->i + 1] != ':') ok = YES;
        if (!ok) break;
        x->i++;
    }
    return x->i > a ? [x->s substringWithRange:NSMakeRange(a, x->i - a)] : nil;
}

typedef enum { AX_CHILD, AX_DESC, AX_DESC_SELF, AX_SELF, AX_PARENT, AX_ATTR, AX_ANCESTOR, AX_ANCESTOR_SELF, AX_FOLLOWING_SIB, AX_PRECEDING_SIB } Axis;

static void collect_desc(NSXMLNode *n, NSMutableArray *out) {
    for (NSXMLNode *c in n->_children) {
        [out addObject:c];
        collect_desc(c, out);
    }
}
static NSArray *axis_nodes(NSXMLNode *n, Axis ax) {
    NSMutableArray *out = [NSMutableArray array];
    switch (ax) {
    case AX_CHILD: if (n->_children) [out addObjectsFromArray:n->_children]; break;
    case AX_DESC: collect_desc(n, out); break;
    case AX_DESC_SELF: [out addObject:n]; collect_desc(n, out); break;
    case AX_SELF: [out addObject:n]; break;
    case AX_PARENT: if (n->_parent) [out addObject:n->_parent]; break;
    case AX_ATTR: if (n->_kind == NSXMLElementKind) [out addObjectsFromArray:((NSXMLElement *)n)->_attributes]; break;
    case AX_ANCESTOR_SELF: [out addObject:n]; /* fall through */
    case AX_ANCESTOR: for (NSXMLNode *p = n->_parent; p; p = p->_parent) [out addObject:p]; break;
    case AX_FOLLOWING_SIB: for (NSXMLNode *s = n.nextSibling; s; s = s.nextSibling) [out addObject:s]; break;
    case AX_PRECEDING_SIB: for (NSXMLNode *s = n.previousSibling; s; s = s.previousSibling) [out addObject:s]; break;
    }
    return out;
}

static BNXPValue *xp_expr(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size);

/* name test against a node on an axis (attributes on the attribute axis, elements elsewhere) */
static BOOL name_test(XP *x, NSXMLNode *n, NSString *test, Axis ax) {
    NSXMLNodeKind want = ax == AX_ATTR ? NSXMLAttributeKind : NSXMLElementKind;
    if (n->_kind != want) return NO;
    if ([test isEqual:@"*"]) return YES;
    NSString *prefix = [NSXMLNode prefixForName:test], *local = [NSXMLNode localNameForName:test];
    if ([local isEqual:@"*"] && prefix.length) {
        NSString *uri = [x->context isKindOfClass:[NSXMLElement class]] ? [(NSXMLElement *)x->context resolvePrefixForNamespace:prefix] : nil;
        return uri ? [n.URI isEqual:uri] : [n.prefix isEqual:prefix];
    }
    if (![n.localName isEqual:local]) return NO;
    if (prefix.length) {
        /* the prefix as declared where the query runs (or on the node itself) */
        NSXMLElement *scope = (NSXMLElement *)([x->context isKindOfClass:[NSXMLElement class]] ? x->context : x->context.rootDocument.rootElement);
        NSString *uri = [scope resolvePrefixForNamespace:prefix];
        if (!uri && n->_kind == NSXMLElementKind) uri = [(NSXMLElement *)n resolvePrefixForNamespace:prefix];
        if (!uri && n->_kind == NSXMLAttributeKind && n->_parent) uri = [(NSXMLElement *)n->_parent resolvePrefixForNamespace:prefix];
        return uri ? [n.URI isEqual:uri] : [n.prefix isEqual:prefix];
    }
    return n.prefix.length == 0 && !n.URI.length; /* an unprefixed test means no namespace */
}

/* moves to the ']' closing a predicate whose '[' was just read */
static BOOL skip_predicate(XP *x) {
    int depth = 0;
    unichar q = 0;
    while (x->i < x->s.length) {
        unichar c = [x->s characterAtIndex:x->i];
        if (q) { if (c == q) q = 0; }
        else if (c == '"' || c == '\'') q = c;
        else if (c == '[') depth++;
        else if (c == ']') { if (!depth) return YES; depth--; }
        x->i++;
    }
    x->error = @"']' expected";
    return NO;
}

/* one step from each context node; returns nil on a syntax error */
static NSArray *xp_step(XP *x, NSArray *contexts, Axis defaultAxis) {
    Axis ax = defaultAxis;
    NSString *test = nil;
    int kindTest = 0; /* 1 node(), 2 text(), 3 comment(), 4 processing-instruction() */
    if (xp_eat(x, @"..")) { ax = AX_PARENT; kindTest = 1; }
    else if (xp_peek(x) == '.' && !(x->i + 1 < x->s.length && [x->s characterAtIndex:x->i + 1] == '.')) { x->i++; ax = defaultAxis == AX_DESC ? AX_DESC_SELF : AX_SELF; kindTest = 1; }
    else {
        if (xp_eat(x, @"@")) ax = AX_ATTR;
        else {
            NSUInteger save = x->i;
            NSString *axisName = xp_name(x);
            if (axisName && xp_eat(x, @"::")) {
                NSDictionary *axes = @{@"child" : @(AX_CHILD), @"descendant" : @(AX_DESC), @"descendant-or-self" : @(AX_DESC_SELF),
                                       @"self" : @(AX_SELF), @"parent" : @(AX_PARENT), @"attribute" : @(AX_ATTR),
                                       @"ancestor" : @(AX_ANCESTOR), @"ancestor-or-self" : @(AX_ANCESTOR_SELF),
                                       @"following-sibling" : @(AX_FOLLOWING_SIB), @"preceding-sibling" : @(AX_PRECEDING_SIB)};
                NSNumber *a = axes[axisName];
                if (!a) { x->error = [@"unsupported axis " stringByAppendingString:axisName]; return nil; }
                ax = (Axis)a.intValue;
                if (defaultAxis == AX_DESC && ax == AX_CHILD) ax = AX_DESC;
            } else {
                x->i = save;
            }
        }
        if (xp_eat(x, @"*")) test = @"*";
        else {
            test = xp_name(x);
            if (!test) { x->error = @"name expected"; return nil; }
            if (xp_eat(x, @"(")) {
                if (!xp_eat(x, @")")) { x->error = @"')' expected"; return nil; }
                if ([test isEqual:@"node"]) kindTest = 1;
                else if ([test isEqual:@"text"]) kindTest = 2;
                else if ([test isEqual:@"comment"]) kindTest = 3;
                else if ([test isEqual:@"processing-instruction"]) kindTest = 4;
                else { x->error = [@"unsupported node test " stringByAppendingString:test]; return nil; }
                test = nil;
            } else if (xp_eat(x, @":*")) {
                test = [test stringByAppendingString:@":*"];
            }
        }
    }
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set]; /* nodes compare by identity */
    NSUInteger predStart = x->i;
    if (!contexts.count) { /* nothing to filter: just move past the predicates */
        while (xp_eat(x, @"[")) {
            if (!skip_predicate(x) || !xp_eat(x, @"]")) { if (!x->error) x->error = @"']' expected"; return nil; }
        }
        return result;
    }
    for (NSXMLNode *c in contexts) {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSXMLNode *n in axis_nodes(c, ax)) {
            BOOL ok;
            switch (kindTest) {
            case 1: ok = YES; break;
            case 2: ok = n->_kind == NSXMLTextKind; break;
            case 3: ok = n->_kind == NSXMLCommentKind; break;
            case 4: ok = n->_kind == NSXMLProcessingInstructionKind; break;
            default: ok = name_test(x, n, test, ax);
            }
            if (ok) [matched addObject:n];
        }
        /* predicates, each over the previous one's result */
        x->i = predStart;
        while (xp_eat(x, @"[")) {
            NSUInteger exprStart = x->i;
            NSMutableArray *kept = [NSMutableArray array];
            NSUInteger size = matched.count;
            if (!size && !skip_predicate(x)) return nil;
            for (NSUInteger k = 0; k < size; k++) {
                x->i = exprStart;
                BNXPValue *v = xp_expr(x, matched[k], k + 1, size);
                if (!v) return nil;
                BOOL keep = v->kind == V_NUMBER ? (v->number == (double)(k + 1)) : as_bool(v);
                if (keep) [kept addObject:matched[k]];
            }
            if (x->error) return nil;
            if (!xp_eat(x, @"]")) { x->error = @"']' expected"; return nil; }
            matched = kept;
        }
        for (NSXMLNode *n in matched)
            if (![seen containsObject:n]) {
                [seen addObject:n];
                [result addObject:n];
            }
    }
    return result;
}

/* a location path from the context; absolute when it starts with '/' */
static NSArray *xp_path(XP *x, NSXMLNode *ctx) {
    NSArray *nodes;
    Axis next = AX_CHILD;
    xp_ws(x);
    if (xp_eat(x, @"//")) {
        NSXMLNode *root = ctx;
        while (root->_parent) root = root->_parent;
        nodes = @[ root ];
        next = AX_DESC;
    } else if (xp_eat(x, @"/")) {
        NSXMLNode *root = ctx;
        while (root->_parent) root = root->_parent;
        nodes = @[ root ];
        unichar c = xp_peek(x);
        if (!c || c == '|' || c == ')' || c == ']') return nodes; /* just "/" */
    } else {
        nodes = @[ ctx ];
    }
    for (;;) {
        nodes = xp_step(x, nodes, next);
        if (!nodes) return nil;
        if (xp_eat(x, @"//")) next = AX_DESC;
        else if (xp_eat(x, @"/")) next = AX_CHILD;
        else break;
    }
    return nodes;
}

static BOOL compare(BNXPValue *a, BNXPValue *b, NSString *op) {
    /* node-sets compare by any member's string value */
    if (a->kind == V_NODES || b->kind == V_NODES) {
        BNXPValue *ns = a->kind == V_NODES ? a : b, *other = a->kind == V_NODES ? b : a;
        BOOL flip = a->kind != V_NODES;
        for (NSXMLNode *n in ns->nodes) {
            BNXPValue *s = v_string(n.stringValue);
            if (other->kind == V_NODES) {
                for (NSXMLNode *m in other->nodes)
                    if (compare(s, v_string(m.stringValue), op)) return YES;
                continue;
            }
            if (other->kind == V_NUMBER) s = v_number(as_number(s));
            if (flip ? compare(other, s, op) : compare(s, other, op)) return YES;
        }
        return NO;
    }
    if ([op isEqual:@"="] || [op isEqual:@"!="]) {
        BOOL eq;
        if (a->kind == V_BOOL || b->kind == V_BOOL) eq = as_bool(a) == as_bool(b);
        else if (a->kind == V_NUMBER || b->kind == V_NUMBER) eq = as_number(a) == as_number(b);
        else eq = [as_string(a) isEqual:as_string(b)];
        return [op isEqual:@"="] ? eq : !eq;
    }
    double l = as_number(a), r = as_number(b);
    if ([op isEqual:@"<"]) return l < r;
    if ([op isEqual:@"<="]) return l <= r;
    if ([op isEqual:@">"]) return l > r;
    return l >= r;
}

static BNXPValue *xp_primary(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    unichar c = xp_peek(x);
    if (c == '(') {
        x->i++;
        BNXPValue *v = xp_expr(x, ctx, pos, size);
        if (!v || !xp_eat(x, @")")) { if (!x->error) x->error = @"')' expected"; return nil; }
        return v;
    }
    if (c == '"' || c == '\'') {
        NSUInteger a = ++x->i;
        while (x->i < x->s.length && [x->s characterAtIndex:x->i] != c) x->i++;
        if (x->i >= x->s.length) { x->error = @"unterminated string"; return nil; }
        NSString *lit = [x->s substringWithRange:NSMakeRange(a, x->i - a)];
        x->i++;
        return v_string(lit);
    }
    if ((c >= '0' && c <= '9') || (c == '.' && x->i + 1 < x->s.length && [x->s characterAtIndex:x->i + 1] >= '0' && [x->s characterAtIndex:x->i + 1] <= '9')) {
        NSUInteger a = x->i;
        while (x->i < x->s.length && (([x->s characterAtIndex:x->i] >= '0' && [x->s characterAtIndex:x->i] <= '9') || [x->s characterAtIndex:x->i] == '.')) x->i++;
        return v_number([[x->s substringWithRange:NSMakeRange(a, x->i - a)] doubleValue]);
    }
    if (c == '-') {
        x->i++;
        BNXPValue *v = xp_primary(x, ctx, pos, size);
        return v ? v_number(-as_number(v)) : nil;
    }
    /* a function call? */
    NSUInteger save = x->i;
    NSString *name = xp_name(x);
    if (name && xp_peek(x) == '(' && ![name isEqual:@"node"] && ![name isEqual:@"text"] && ![name isEqual:@"comment"] &&
        ![name isEqual:@"processing-instruction"]) {
        x->i++;
        NSMutableArray<BNXPValue *> *args = [NSMutableArray array];
        if (!xp_eat(x, @")")) {
            for (;;) {
                BNXPValue *a = xp_expr(x, ctx, pos, size);
                if (!a) return nil;
                [args addObject:a];
                if (xp_eat(x, @")")) break;
                if (!xp_eat(x, @",")) { x->error = @"',' expected"; return nil; }
            }
        }
        NSUInteger n = args.count;
        if ([name isEqual:@"last"]) return v_number(size);
        if ([name isEqual:@"position"]) return v_number(pos);
        if ([name isEqual:@"true"]) return v_bool(YES);
        if ([name isEqual:@"false"]) return v_bool(NO);
        if ([name isEqual:@"not"] && n == 1) return v_bool(!as_bool(args[0]));
        if ([name isEqual:@"boolean"] && n == 1) return v_bool(as_bool(args[0]));
        if ([name isEqual:@"number"]) return v_number(n ? as_number(args[0]) : as_number(v_string(ctx.stringValue)));
        if ([name isEqual:@"string"]) return v_string(n ? as_string(args[0]) : ctx.stringValue);
        if ([name isEqual:@"count"] && n == 1) return v_number(args[0]->kind == V_NODES ? args[0]->nodes.count : 0);
        if ([name isEqual:@"contains"] && n == 2) {
            NSString *h = as_string(args[0]), *nd = as_string(args[1]);
            return v_bool(!nd.length || [h rangeOfString:nd].location != NSNotFound);
        }
        if ([name isEqual:@"starts-with"] && n == 2) return v_bool([as_string(args[0]) hasPrefix:as_string(args[1])]);
        if ([name isEqual:@"concat"]) {
            NSMutableString *s = [NSMutableString string];
            for (BNXPValue *a in args) [s appendString:as_string(a)];
            return v_string(s);
        }
        if ([name isEqual:@"string-length"]) return v_number((n ? as_string(args[0]) : ctx.stringValue).length);
        if ([name isEqual:@"normalize-space"]) {
            NSString *s = n ? as_string(args[0]) : ctx.stringValue;
            NSMutableArray *words = [NSMutableArray array];
            for (NSString *w in [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])
                if (w.length) [words addObject:w];
            return v_string([words componentsJoinedByString:@" "]);
        }
        if ([name isEqual:@"name"] || [name isEqual:@"local-name"] || [name isEqual:@"namespace-uri"]) {
            NSXMLNode *t = n ? (args[0]->kind == V_NODES && args[0]->nodes.count ? args[0]->nodes[0] : nil) : ctx;
            if ([name isEqual:@"name"]) return v_string(t.name);
            if ([name isEqual:@"local-name"]) return v_string(t.localName);
            return v_string(t.URI);
        }
        x->error = [NSString stringWithFormat:@"unsupported function %@()", name];
        return nil;
    }
    x->i = save;
    NSArray *nodes = xp_path(x, ctx);
    return nodes ? v_nodes(nodes) : nil;
}

static BNXPValue *xp_union(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    BNXPValue *v = xp_primary(x, ctx, pos, size);
    while (v && xp_peek(x) == '|') {
        x->i++;
        BNXPValue *w = xp_primary(x, ctx, pos, size);
        if (!w) return nil;
        if (v->kind != V_NODES || w->kind != V_NODES) { x->error = @"'|' needs node-sets"; return nil; }
        NSMutableArray *all = [v->nodes mutableCopy];
        for (NSXMLNode *n in w->nodes)
            if ([all indexOfObjectIdenticalTo:n] == NSNotFound) [all addObject:n];
        v = v_nodes(all);
    }
    return v;
}
static BNXPValue *xp_arith(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    BNXPValue *v = xp_union(x, ctx, pos, size);
    for (;;) {
        if (!v) return nil;
        unichar c = xp_peek(x);
        if (c == '+' || (c == '-' && x->i + 1 < x->s.length)) {
            x->i++;
            BNXPValue *w = xp_union(x, ctx, pos, size);
            if (!w) return nil;
            v = v_number(c == '+' ? as_number(v) + as_number(w) : as_number(v) - as_number(w));
        } else if (xp_eat(x, @"div ") || xp_eat(x, @"mod ")) {
            BOOL div = [[x->s substringWithRange:NSMakeRange(x->i - 4, 3)] isEqual:@"div"];
            BNXPValue *w = xp_union(x, ctx, pos, size);
            if (!w) return nil;
            v = v_number(div ? as_number(v) / as_number(w) : fmod(as_number(v), as_number(w)));
        } else return v;
    }
}
static BNXPValue *xp_cmp(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    BNXPValue *a = xp_arith(x, ctx, pos, size);
    if (!a) return nil;
    for (NSString *op in @[ @"!=", @"<=", @">=", @"=", @"<", @">" ]) {
        if (xp_eat(x, op)) {
            BNXPValue *b = xp_arith(x, ctx, pos, size);
            return b ? v_bool(compare(a, b, op)) : nil;
        }
    }
    return a;
}
static BNXPValue *xp_and(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    BNXPValue *v = xp_cmp(x, ctx, pos, size);
    while (v && xp_eat(x, @"and ")) {
        BNXPValue *w = xp_cmp(x, ctx, pos, size);
        if (!w) return nil;
        v = v_bool(as_bool(v) && as_bool(w));
    }
    return v;
}
static BNXPValue *xp_expr(XP *x, NSXMLNode *ctx, NSUInteger pos, NSUInteger size) {
    BNXPValue *v = xp_and(x, ctx, pos, size);
    while (v && xp_eat(x, @"or ")) {
        BNXPValue *w = xp_and(x, ctx, pos, size);
        if (!w) return nil;
        v = v_bool(as_bool(v) || as_bool(w));
    }
    return v;
}

NSArray *bn_xpath(NSXMLNode *context, NSString *xpath, NSString **why) {
    XP x = {xpath ?: @"", 0, nil, context};
    BNXPValue *v = xp_expr(&x, context, 1, 1);
    xp_ws(&x);
    if (!x.error && x.i < x.s.length) x.error = [NSString stringWithFormat:@"unexpected '%@'", [x.s substringFromIndex:x.i]];
    if (!v || x.error) {
        if (why) *why = x.error ?: @"invalid XPath";
        return nil;
    }
    if (v->kind != V_NODES) {
        if (why) *why = @"the expression is not a node-set";
        return nil;
    }
    /* document order */
    if (v->nodes.count > 1) {
        NSMutableArray *order = [NSMutableArray array];
        NSXMLNode *root = context;
        while (root->_parent) root = root->_parent;
        [order addObject:root];
        __block void (^walk)(NSXMLNode *) = nil;
        void (^w)(NSXMLNode *) = ^(NSXMLNode *n) {
            if (n->_kind == NSXMLElementKind) {
                [order addObjectsFromArray:((NSXMLElement *)n)->_namespaces];
                [order addObjectsFromArray:((NSXMLElement *)n)->_attributes];
            }
            for (NSXMLNode *c in n->_children) {
                [order addObject:c];
                walk(c);
            }
        };
        walk = w;
        walk(root);
        walk = nil;
        return [v->nodes sortedArrayUsingComparator:^NSComparisonResult(NSXMLNode *a, NSXMLNode *b) {
            NSUInteger i = [order indexOfObjectIdenticalTo:a], j = [order indexOfObjectIdenticalTo:b];
            return i < j ? NSOrderedAscending : i > j ? NSOrderedDescending : NSOrderedSame;
        }];
    }
    return v->nodes;
}
