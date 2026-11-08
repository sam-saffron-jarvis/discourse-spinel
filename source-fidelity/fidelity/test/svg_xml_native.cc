// Stateless Ruby-free libxml2 engine for the SvgSprite.symbols_for DOM operations.
// No file/network/PG/process API is exposed; all XML bytes come from verified caller.
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>
#include <memory>
#include <string>
#include <stdexcept>
#include <climits>
#include <cctype>

namespace {
thread_local std::string output, error;
thread_local unsigned long calls = 0, active_documents = 0;
std::string quoted(const std::string &text) {
  std::string result = "\"";
  const char *hex = "0123456789abcdef";
  for (unsigned char c : text) {
    if (c == '"' || c == '\\') { result += '\\'; result += c; }
    else if (c < 0x20) { result += "\\u00"; result += hex[c >> 4]; result += hex[c & 15]; }
    else result += c;
  }
  return result + '"';
}
struct DocumentFree {
  void operator()(xmlDoc *doc) const { xmlFreeDoc(doc); --active_documents; }
};
struct BufferFree { void operator()(xmlBuffer *buffer) const { xmlBufferFree(buffer); } };
struct SaveFree { void operator()(xmlSaveCtxt *save) const { xmlSaveClose(save); } };
void remove_titles(xmlNode *parent) {
  for (xmlNode *node = parent->children; node;) {
    xmlNode *next = node->next;
    if (node->type == XML_ELEMENT_NODE && xmlStrEqual(node->name, BAD_CAST "title")) {
      xmlUnlinkNode(node);
      xmlFreeNode(node);
    } else remove_titles(node);
    node = next;
  }
}
bool blank(const std::string &text) {
  size_t offset = 0;
  while (offset < text.size()) {
    int width = static_cast<int>(text.size() - offset > 4 ? 4 : text.size() - offset);
    int code = xmlGetUTF8Char(reinterpret_cast<const unsigned char *>(text.data() + offset), &width);
    if (code < 0 || width <= 0) return false;
    bool space = (code >= 9 && code <= 13) || code == 32 || code == 0x85 || code == 0xa0 || code == 0x1680 ||
      (code >= 0x2000 && code <= 0x200a) || code == 0x2028 || code == 0x2029 || code == 0x202f || code == 0x205f || code == 0x3000;
    if (!space) return false;
    offset += static_cast<size_t>(width);
  }
  return true;
}
void check_namespaces(xmlNode *node, const std::string &expected) {
  for (; node; node = node->next) {
    if (node->type == XML_ELEMENT_NODE) {
      std::string uri = node->ns && node->ns->href ? reinterpret_cast<const char *>(node->ns->href) : "";
      if (uri != expected) throw std::runtime_error("unacquired mixed SVG XML namespace profile");
    }
    check_namespaces(node->children, expected);
  }
}
void collect(xmlDoc *doc, xmlNode *parent, const std::string &filename, bool &first) {
  for (xmlNode *node = parent; node; node = node->next) {
    if (node->type == XML_ELEMENT_NODE && xmlStrEqual(node->name, BAD_CAST "symbol")) {
      xmlChar *raw_id = xmlGetProp(node, BAD_CAST "id");
      if (!raw_id && (filename == "regular" || filename == "brands"))
        throw std::runtime_error("unsupported missing SVG symbol id for prefixed sprite");
      std::string id = raw_id ? reinterpret_cast<const char *>(raw_id) : "";
      xmlFree(raw_id);
      if (filename == "regular") id = "far-" + id;
      if (filename == "brands") id = "fab-" + id;
      if (!blank(id)) {
        xmlSetProp(node, BAD_CAST "id", BAD_CAST id.c_str());
        xmlSetProp(node, BAD_CAST "overflow", BAD_CAST "visible");
        remove_titles(node);
        std::unique_ptr<xmlBuffer, BufferFree> buffer(xmlBufferCreate());
        if (!buffer) throw std::runtime_error("SVG symbol buffer allocation failed");
        std::unique_ptr<xmlSaveCtxt, SaveFree> save(xmlSaveToBuffer(buffer.get(), nullptr, XML_SAVE_FORMAT | XML_SAVE_AS_XML));
        if (!save || xmlSaveTree(save.get(), node) < 0) throw std::runtime_error("SVG symbol serialization failed");
        if (xmlSaveClose(save.release()) < 0) throw std::runtime_error("SVG symbol output flush failed");
        std::string xml(reinterpret_cast<const char *>(xmlBufferContent(buffer.get())), xmlBufferLength(buffer.get()));
        if (!first) output += ',';
        first = false;
        output += quoted(id) + ':' + quoted(xml);
      }
    }
    collect(doc, node->children, filename, first);
  }
}
}
extern "C" const char *owned_svg_xml_symbols(const char *bytes, long length, const char *filename, int strict) {
  output.clear(); error.clear(); ++calls;
  try {
    if (!bytes || !filename || length < 0 || length > 16 * 1024 * 1024 || length > INT_MAX || (strict != 0 && strict != 1))
      throw std::runtime_error("unsupported SVG XML engine input");
    std::string xml(bytes, static_cast<size_t>(length));
    if (xml.find('\0') != std::string::npos || !xmlCheckUTF8(BAD_CAST xml.c_str()))
      throw std::runtime_error("unacquired non-UTF8 SVG XML profile");
    if (xml.find("<!DOCTYPE") != std::string::npos || xml.find("<!ENTITY") != std::string::npos)
      throw std::runtime_error("unacquired SVG DTD/entity profile");
    // NONET is an admission safeguard, not a fallback result. DTD/entities are
    // refused before parsing. Source strict:true sets NOBLANKS; false uses the
    // Nokogiri default XML recovery mode. No external entity substitution.
    int options = XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING;
    options |= strict ? XML_PARSE_NOBLANKS : XML_PARSE_RECOVER | XML_PARSE_BIG_LINES;
    xmlDoc *parsed = xmlReadMemory(bytes, static_cast<int>(length), filename, nullptr, options);
    if (!parsed) throw std::runtime_error("SVG XML parse failed");
    ++active_documents;
    std::unique_ptr<xmlDoc, DocumentFree> doc(parsed);
    if (doc->intSubset || doc->extSubset) throw std::runtime_error("unacquired SVG DTD profile");
    xmlNode *root = xmlDocGetRootElement(doc.get());
    if (root && root->ns && root->ns->prefix) throw std::runtime_error("unacquired prefixed SVG root namespace profile");
    std::string uri = root && root->ns && root->ns->href ? reinterpret_cast<const char *>(root->ns->href) : "";
    check_namespaces(root, uri);
    output = "{";
    bool first = true;
    collect(doc.get(), xmlDocGetRootElement(doc.get()), filename, first);
    output += '}';
    return output.c_str();
  } catch (const std::exception &exception) {
    error = exception.what(); output.clear(); return output.c_str();
  }
}
extern "C" const char *owned_svg_xml_error() { return error.c_str(); }
extern "C" long owned_svg_xml_active_documents() { return static_cast<long>(active_documents); }
extern "C" long owned_svg_xml_calls() { return static_cast<long>(calls); }
extern "C" const char *owned_svg_xml_version() { return LIBXML_DOTTED_VERSION; }
