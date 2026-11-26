// NSXMLParser events and errors; NSXMLDocument, NSXMLElement and NSXMLNode;
// XPath over an appcast like the ones update frameworks read.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
#define EQ(a, b) do { NSString *a_ = (a), *b_ = (b); if (![a_ isEqual:b_]) { printf("FAIL %s:%d: \"%s\" != \"%s\"\n", __FILE__, __LINE__, a_.UTF8String, b_.UTF8String); exit(1); } } while (0)

@interface Recorder : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic) BOOL abortAtB;
@property (nonatomic, strong) NSError *error;
@end
@implementation Recorder
- (instancetype)init {
    if ((self = [super init])) { _events = [NSMutableArray array]; _text = [NSMutableString string]; }
    return self;
}
- (void)flush {
    if (_text.length) [_events addObject:[NSString stringWithFormat:@"text(%@)", _text]];
    [_text setString:@""];
}
- (void)parserDidStartDocument:(NSXMLParser *)p { [_events addObject:@"start"]; }
- (void)parserDidEndDocument:(NSXMLParser *)p { [self flush]; [_events addObject:@"end"]; }
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q attributes:(NSDictionary *)attrs {
    [self flush];
    NSMutableArray *keys = [[attrs.allKeys sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in keys) [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, attrs[k]]];
    [_events addObject:[NSString stringWithFormat:@"<%@ %@ %@ {%@}>", name, uri ?: @"-", q ?: @"-", [pairs componentsJoinedByString:@","]]];
    if (_abortAtB && [name isEqual:@"b"]) [p abortParsing];
}
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q {
    [self flush];
    [_events addObject:[NSString stringWithFormat:@"</%@>", name]];
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [_text appendString:s]; }
- (void)parser:(NSXMLParser *)p foundCDATA:(NSData *)d {
    [self flush];
    [_events addObject:[NSString stringWithFormat:@"cdata(%@)", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]]];
}
- (void)parser:(NSXMLParser *)p foundComment:(NSString *)c { [self flush]; [_events addObject:[NSString stringWithFormat:@"comment(%@)", c]]; }
- (void)parser:(NSXMLParser *)p foundProcessingInstructionWithTarget:(NSString *)t data:(NSString *)d {
    [self flush];
    [_events addObject:[NSString stringWithFormat:@"pi(%@,%@)", t, d]];
}
- (void)parser:(NSXMLParser *)p didStartMappingPrefix:(NSString *)prefix toURI:(NSString *)uri {
    [_events addObject:[NSString stringWithFormat:@"map(%@=%@)", prefix, uri]];
}
- (void)parser:(NSXMLParser *)p didEndMappingPrefix:(NSString *)prefix { [_events addObject:[NSString stringWithFormat:@"unmap(%@)", prefix]]; }
- (void)parser:(NSXMLParser *)p parseErrorOccurred:(NSError *)e { _error = e; }
@end

static NSString *run(NSString *xml, BOOL ns, BOOL report, Recorder **out, BOOL *ok) {
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    Recorder *r = [Recorder new];
    p.delegate = r;
    p.shouldProcessNamespaces = ns;
    p.shouldReportNamespacePrefixes = report;
    BOOL result = [p parse];
    if (ok) *ok = result;
    if (out) *out = r;
    if (!result) r.error = p.parserError;
    return [r.events componentsJoinedByString:@" "];
}
static NSInteger error_code(NSString *xml) {
    Recorder *r;
    BOOL ok;
    run(xml, NO, NO, &r, &ok);
    return ok ? 0 : r.error.code;
}

static NSString *appcast =
    @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
    @"<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
    @"  <channel>\n"
    @"    <title>Changelog</title>\n"
    @"    <item>\n"
    @"      <title>Version 2.0</title>\n"
    @"      <sparkle:version>200</sparkle:version>\n"
    @"      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
    @"      <description><![CDATA[<ul><li>New & shiny</li></ul>]]></description>\n"
    @"      <enclosure url=\"https://example.com/App-2.0.dmg\" length=\"1234\" type=\"application/octet-stream\" sparkle:edSignature=\"abc==\"/>\n"
    @"    </item>\n"
    @"    <item>\n"
    @"      <title>Version 1.9</title>\n"
    @"      <sparkle:version>190</sparkle:version>\n"
    @"      <enclosure url=\"https://example.com/App-1.9.dmg\" length=\"999\"/>\n"
    @"    </item>\n"
    @"  </channel>\n"
    @"</rss>\n";

int main(void) {
    /* ---- events ---- */
    BOOL ok;
    Recorder *r;
    NSString *ev = run(@"<?xml version='1.0'?><!-- hi --><a x='1' y=\"a&amp;b\">t&lt;1 &#65;&#x42;<b/>u<![CDATA[<raw>]]><?go now?></a>", NO, NO, &r, &ok);
    CHECK(ok);
    EQ(ev, @"start comment( hi ) <a - - {x=1,y=a&b}> text(t<1 AB) <b - - {}> </b> text(u) cdata(<raw>) pi(go,now) </a> end");
    /* namespaces: off, then on, then with mappings */
    NSString *nsxml = @"<r xmlns='urn:d' xmlns:p='urn:p'><p:e p:k='v' k2='w'/></r>";
    EQ(run(nsxml, NO, NO, NULL, NULL), @"start <r - - {xmlns=urn:d,xmlns:p=urn:p}> <p:e - - {k2=w,p:k=v}> </p:e> </r> end");
    EQ(run(nsxml, YES, NO, NULL, NULL), @"start <r urn:d r {}> <e urn:p p:e {k2=w,p:k=v}> </e> </r> end");
    EQ(run(nsxml, YES, YES, NULL, NULL), @"start map(=urn:d) map(p=urn:p) <r urn:d r {}> <e urn:p p:e {k2=w,p:k=v}> </e> </r> unmap() unmap(p) end");
    EQ(run(@"<a><b>x</b></a>", YES, NO, NULL, NULL), @"start <a  a {}> <b  b {}> text(x) </b> </a> end");
    /* line ends, attribute whitespace, internal entities, BOM */
    EQ(run(@"<a v='1\n2'>x\r\ny\rz</a>", NO, NO, NULL, NULL), @"start <a - - {v=1 2}> text(x\ny\nz) </a> end");
    EQ(run(@"<!DOCTYPE a [<!ENTITY me \"bitten &#169;\"><!ELEMENT a (#PCDATA)>]><a>&me;</a>", NO, NO, NULL, NULL),
       @"start <a - - {}> text(bitten ©) </a> end");
    NSMutableData *bom = [NSMutableData dataWithBytes:"\xef\xbb\xbf" length:3];
    [bom appendData:[@"<a>é</a>" dataUsingEncoding:NSUTF8StringEncoding]];
    NSXMLParser *bp = [[NSXMLParser alloc] initWithData:bom];
    Recorder *br = [Recorder new];
    bp.delegate = br;
    CHECK([bp parse] && [[br.events componentsJoinedByString:@" "] isEqual:@"start <a - - {}> text(é) </a> end"]);
    static const char latin1Bytes[] = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><a>\xe9</a>";
    NSData *latin1 = [NSData dataWithBytes:latin1Bytes length:strlen(latin1Bytes)];
    bp = [[NSXMLParser alloc] initWithData:latin1];
    br = [Recorder new];
    bp.delegate = br;
    CHECK([bp parse] && [br.events containsObject:@"text(é)"]);
    /* errors */
    CHECK(error_code(@"") == NSXMLParserEmptyDocumentError);
    CHECK(error_code(@"<a><b></a>") == NSXMLParserTagNameMismatchError);
    CHECK(error_code(@"<a>") == NSXMLParserPrematureDocumentEndError);
    CHECK(error_code(@"<a/><b/>") == NSXMLParserPrematureDocumentEndError);
    CHECK(error_code(@"<a>&nope;</a>") == NSXMLParserUndeclaredEntityError);
    CHECK(error_code(@"<a x='1' x='2'/>") == NSXMLParserAttributeRedefinedError);
    CHECK(error_code(@"<a x/>") == NSXMLParserAttributeWithoutValueError);
    CHECK(error_code(@"<a x='<'/>") == NSXMLParserLessThanSymbolInAttributeError);
    CHECK(error_code(@"<a><!-- x</a>") == NSXMLParserCommentNotFinishedError);
    CHECK(error_code(@"text") == NSXMLParserEmptyDocumentError || error_code(@"text") == NSXMLParserDocumentStartError);
    run(@"<a>\n<b></c></a>", NO, NO, &r, &ok);
    CHECK(!ok && [r.error.domain isEqual:NSXMLParserErrorDomain] && [r.error.userInfo[@"NSXMLParserErrorLineNumber"] integerValue] == 2);
    /* abort */
    Recorder *ar = [Recorder new];
    ar.abortAtB = YES;
    NSXMLParser *ap = [[NSXMLParser alloc] initWithData:[@"<a><b/><c/></a>" dataUsingEncoding:NSUTF8StringEncoding]];
    ap.delegate = ar;
    CHECK(![ap parse] && ap.parserError.code == NSXMLParserDelegateAbortedParseError);
    CHECK(![ar.events containsObject:@"<c - - {}>"]);

    /* ---- the tree ---- */
    NSError *err = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:appcast options:NSXMLNodeLoadExternalEntitiesNever error:&err];
    CHECK(doc && !err);
    EQ(doc.characterEncoding, @"utf-8");
    NSXMLElement *rss = doc.rootElement;
    EQ(rss.name, @"rss");
    CHECK(rss.childCount == 1 && rss.kind == NSXMLElementKind && rss.level == 1 && rss.rootDocument == doc);
    EQ([rss attributeForName:@"version"].stringValue, @"2.0");
    EQ([rss namespaceForPrefix:@"sparkle"].stringValue, @"http://www.andymatuschak.org/xml-namespaces/sparkle");
    NSArray<NSXMLElement *> *items = (NSArray *)[doc nodesForXPath:@"/rss/channel/item" error:&err];
    CHECK(items.count == 2);
    NSXMLElement *item = items[0];
    /* walking children the way update frameworks do */
    NSMutableArray *names = [NSMutableArray array];
    for (NSXMLNode *n = [item childAtIndex:0]; n; n = n.nextSibling)
        if (n.kind == NSXMLElementKind) [names addObject:[NSString stringWithFormat:@"%@|%@|%@", n.name, n.localName, n.URI ?: @"-"]];
    EQ([names componentsJoinedByString:@" "],
       @"title|title|- sparkle:version|version|http://www.andymatuschak.org/xml-namespaces/sparkle "
       @"sparkle:minimumSystemVersion|minimumSystemVersion|http://www.andymatuschak.org/xml-namespaces/sparkle "
       @"description|description|- enclosure|enclosure|-");
    EQ([item elementsForName:@"sparkle:version"].firstObject.stringValue, @"200");
    EQ([item elementsForLocalName:@"version" URI:@"http://www.andymatuschak.org/xml-namespaces/sparkle"].firstObject.stringValue, @"200");
    EQ([item elementsForName:@"description"].firstObject.stringValue, @"<ul><li>New & shiny</li></ul>");
    NSXMLElement *enc = [item elementsForName:@"enclosure"].firstObject;
    EQ([enc attributeForName:@"url"].stringValue, @"https://example.com/App-2.0.dmg");
    NSXMLNode *sig = [enc attributeForName:@"sparkle:edSignature"];
    EQ(sig.stringValue, @"abc==");
    EQ(sig.localName, @"edSignature");
    EQ(sig.URI, @"http://www.andymatuschak.org/xml-namespaces/sparkle");
    CHECK(enc.attributes.count == 4);
    /* XPath */
    EQ([[doc nodesForXPath:@"//item[2]/title" error:NULL].firstObject stringValue], @"Version 1.9");
    EQ([[doc nodesForXPath:@"/rss/channel/item[last()]/sparkle:version" error:NULL].firstObject stringValue], @"190");
    EQ([[doc nodesForXPath:@"//enclosure[@length='999']/@url" error:NULL].firstObject stringValue], @"https://example.com/App-1.9.dmg");
    CHECK([doc nodesForXPath:@"//item[sparkle:minimumSystemVersion]" error:NULL].count == 1);
    CHECK([doc nodesForXPath:@"//item[sparkle:version > 195]" error:NULL].count == 1);
    CHECK([doc nodesForXPath:@"//item[not(sparkle:minimumSystemVersion)]/title" error:NULL].count == 1);
    CHECK([doc nodesForXPath:@"//title[contains(., '2.0') or starts-with(., 'Change')]" error:NULL].count == 2);
    CHECK([doc nodesForXPath:@"count(//item)" error:&err] == nil && err != nil);
    CHECK([doc nodesForXPath:@"//enclosure/@*" error:NULL].count == 6);
    CHECK([item nodesForXPath:@"./title" error:NULL].count == 1);
    CHECK([item nodesForXPath:@"../title" error:NULL].count == 1);
    EQ([[item nodesForXPath:@"title/text()" error:NULL].firstObject stringValue], @"Version 2.0");
    CHECK([doc nodesForXPath:@"//nothing" error:NULL].count == 0);
    CHECK([doc nodesForXPath:@"//nothing[1]" error:NULL].count == 0);
    CHECK([doc nodesForXPath:@"//item[" error:NULL] == nil);
    EQ(items[1].XPath, @"/rss[1]/channel[1]/item[2]");
    EQ(((NSXMLNode *)[doc nodesForXPath:@"/" error:NULL].firstObject).XPath, @"/");

    /* building and writing */
    NSXMLElement *root = [NSXMLElement elementWithName:@"root"];
    [root addNamespace:[NSXMLNode namespaceWithName:@"x" stringValue:@"urn:x"]];
    [root addAttribute:[NSXMLNode attributeWithName:@"a" stringValue:@"1 < 2 & \"q\""]];
    NSXMLElement *child = [NSXMLElement elementWithName:@"x:child" stringValue:@"a & b"];
    [root addChild:child];
    [root addChild:[NSXMLNode commentWithStringValue:@"note"]];
    [root addChild:[NSXMLElement elementWithName:@"empty"]];
    EQ(root.XMLString, @"<root xmlns:x=\"urn:x\" a=\"1 &lt; 2 &amp; &quot;q&quot;\"><x:child>a &amp; b</x:child><!--note--><empty></empty></root>");
    EQ([root XMLStringWithOptions:NSXMLNodeCompactEmptyElement], @"<root xmlns:x=\"urn:x\" a=\"1 &lt; 2 &amp; &quot;q&quot;\"><x:child>a &amp; b</x:child><!--note--><empty/></root>");
    EQ(child.URI, @"urn:x");
    NSXMLDocument *made = [[NSXMLDocument alloc] initWithRootElement:root];
    made.characterEncoding = @"UTF-8";
    EQ([[NSString alloc] initWithData:made.XMLData encoding:NSUTF8StringEncoding],
       [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" stringByAppendingString:root.XMLString]);
    /* and back */
    NSXMLDocument *again = [[NSXMLDocument alloc] initWithData:made.XMLData options:0 error:&err];
    EQ(again.rootElement.XMLString, root.XMLString);
    EQ([(NSXMLElement *)[NSXMLElement elementWithName:@"p" stringValue:@"x"] stringValue], @"x");
    root.stringValue = @"plain";
    CHECK(root.childCount == 1 && [root.stringValue isEqual:@"plain"]);
    [child detach];
    CHECK(child.parent == nil);
    NSXMLElement *parsed = [[NSXMLElement alloc] initWithXMLString:@"<q n='1'><r/></q>" error:&err];
    CHECK(parsed && parsed.parent == nil && parsed.childCount == 1);
    NSXMLElement *copy = [parsed copy];
    CHECK(copy != parsed && [copy.XMLString isEqual:parsed.XMLString]);
    /* whitespace */
    NSXMLDocument *ws = [[NSXMLDocument alloc] initWithXMLString:@"<a>\n  <b/>\n</a>" options:0 error:NULL];
    CHECK(ws.rootElement.childCount == 1);
    ws = [[NSXMLDocument alloc] initWithXMLString:@"<a>\n  <b/>\n</a>" options:NSXMLNodePreserveWhitespace error:NULL];
    CHECK(ws.rootElement.childCount == 3);
    CHECK([[NSXMLDocument alloc] initWithXMLString:@"<a>" options:0 error:&err] == nil && err.code == NSXMLParserPrematureDocumentEndError);

    puts("xml ok");
    return 0;
}
