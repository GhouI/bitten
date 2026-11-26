// XMLParser with a Swift delegate, and XMLDocument with XPath, as Swift
// programs use them.
import Foundation

final class Collector: NSObject, XMLParserDelegate {
  var names: [String] = []
  var text = ""
  var error: Error?
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
              qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    names.append(elementName + (attributeDict["id"].map { "#" + $0 } ?? ""))
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { error = parseError }
}

@_silgen_name("swl_xml_parser") public func parserTest() -> Int {
  var bad = 0
  let p = XMLParser(data: Data("<list><item id='1'>a</item><item id='2'>b &amp; c</item></list>".utf8))
  let c = Collector()
  p.delegate = c
  if !p.parse() { bad |= 1 }
  if c.names != ["list", "item#1", "item#2"] { bad |= 2 }
  if c.text != "ab & c" { bad |= 4 }
  let q = XMLParser(data: Data("<a><b></a>".utf8))
  let d = Collector()
  q.delegate = d
  if q.parse() { bad |= 8 }
  if (q.parserError as NSError?)?.code != XMLParser.ErrorCode.tagNameMismatchError.rawValue { bad |= 0x10 }
  if (d.error as NSError?)?.domain != XMLParser.errorDomain { bad |= 0x20 }
  return bad
}

@_silgen_name("swl_xml_document") public func documentTest() -> Int {
  var bad = 0
  let xml = "<feed xmlns:x='urn:x'><entry x:n='1'><t>One</t></entry><entry x:n='2'><t>Two</t></entry></feed>"
  guard let doc = try? XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever]) else { return 1 }
  guard let entries = try? doc.nodes(forXPath: "//entry") as? [XMLElement] else { return 2 }
  if entries.count != 2 { bad |= 4 }
  if entries.last?.attribute(forName: "x:n")?.stringValue != "2" { bad |= 8 }
  if entries.first?.elements(forName: "t").first?.stringValue != "One" { bad |= 0x10 }
  if (try? doc.nodes(forXPath: "//entry[@x:n='2']/t"))?.first?.stringValue != "Two" { bad |= 0x20 }
  if doc.rootElement()?.name != "feed" || doc.rootElement()?.kind != .element { bad |= 0x40 }
  let e = XMLElement(name: "made", stringValue: "1 < 2")
  e.addAttribute(XMLNode.attribute(withName: "k", stringValue: "v") as! XMLNode)
  if e.xmlString != "<made k=\"v\">1 &lt; 2</made>" { bad |= 0x80 }
  do {
    _ = try XMLDocument(xmlString: "<open>", options: [])
    bad |= 0x100
  } catch {}
  return bad
}
