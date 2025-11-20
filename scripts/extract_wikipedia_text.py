#!/usr/bin/env python3
"""
Extract plain text from Wikipedia XML dump for frequency analysis.

This is a simplified alternative to wikiextractor that works with modern Python.
"""

import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def clean_wiki_markup(text: str) -> str:
    """Remove Wikipedia markup from text."""
    # Remove HTML comments
    text = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)

    # Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)

    # Remove Wikipedia templates {{...}}
    # This is a simplified removal that handles nested templates
    while '{{' in text:
        text = re.sub(r'\{\{[^{}]*\}\}', '', text)

    # Remove Wikipedia links [[...]] but keep the display text
    text = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', text)

    # Remove external links [http://...]
    text = re.sub(r'\[https?://[^\s\]]+\s*([^\]]*)\]', r'\1', text)

    # Remove references <ref>...</ref>
    text = re.sub(r'<ref[^>]*>.*?</ref>', '', text, flags=re.DOTALL)
    text = re.sub(r'<ref[^>]*\s*/>', '', text)

    # Remove MediaWiki markup
    text = re.sub(r"'''?", '', text)  # Bold and italic
    text = re.sub(r'^[*#:;]+', '', text, flags=re.MULTILINE)  # Lists
    text = re.sub(r'^=+.*?=+\s*$', '', text, flags=re.MULTILINE)  # Headers

    # Remove file references
    text = re.sub(r'(File|ファイル|画像):[^\n]+', '', text)

    # Remove category tags
    text = re.sub(r'\[\[Category:.*?\]\]', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\[\[カテゴリ:.*?\]\]', '', text)

    # Clean up whitespace
    text = re.sub(r'\n+', '\n', text)
    text = re.sub(r' +', ' ', text)

    return text.strip()


def extract_text_from_xml(xml_file: Path, output_file: Path, max_articles: int = None):
    """
    Extract text from Wikipedia XML dump.

    Args:
        xml_file: Path to Wikipedia XML file
        output_file: Path to save extracted text
        max_articles: Maximum number of articles to process (None = all)
    """
    print(f"📖 Extracting text from: {xml_file.name}")
    print(f"   Output: {output_file}")
    if max_articles:
        print(f"   Max articles: {max_articles:,}")

    # Wikipedia XML namespace (try both 0.10 and 0.11)
    # We'll detect it from the file
    with open(xml_file, 'rb') as f:
        header = f.read(500).decode('utf-8', errors='ignore')
        if 'export-0.11' in header:
            namespace = 'http://www.mediawiki.org/xml/export-0.11/'
        else:
            namespace = 'http://www.mediawiki.org/xml/export-0.10/'

    ns = {'mw': namespace}
    print(f"   Using namespace: {namespace}")

    articles_processed = 0
    total_chars = 0

    with open(output_file, 'w', encoding='utf-8') as out:
        # Use iterparse to handle large files efficiently
        context = ET.iterparse(str(xml_file), events=('end',))

        for event, elem in context:
            if elem.tag == f'{{{namespace}}}page':
                # Get title
                title_elem = elem.find('mw:title', ns)
                title = title_elem.text if title_elem is not None else ''

                # Skip special pages
                if ':' in title and any(prefix in title for prefix in [
                    'Wikipedia:', 'Category:', 'Template:', 'Help:', 'Portal:',
                    'ウィキペディア:', 'カテゴリ:', 'テンプレート:', 'ヘルプ:',
                    'File:', 'ファイル:', 'MediaWiki:', 'Special:'
                ]):
                    elem.clear()
                    continue

                # Get text content
                revision = elem.find('mw:revision', ns)
                if revision is not None:
                    text_elem = revision.find('mw:text', ns)
                    if text_elem is not None and text_elem.text:
                        # Clean and extract text
                        text = clean_wiki_markup(text_elem.text)

                        if text.strip():
                            out.write(text + '\n')
                            total_chars += len(text)
                            articles_processed += 1

                            if articles_processed % 1000 == 0:
                                print(f"  Processed {articles_processed:,} articles, {total_chars / 1024 / 1024:.1f} MB")

                            if max_articles and articles_processed >= max_articles:
                                break

                # Clear element to free memory
                elem.clear()

    print(f"\n✅ Extraction complete!")
    print(f"   Articles processed: {articles_processed:,}")
    print(f"   Total text: {total_chars / 1024 / 1024:.2f} MB")
    print(f"   Output file: {output_file}")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 extract_wikipedia_text.py <wikipedia.xml> [max_articles]")
        print("")
        print("Example:")
        print("  python3 extract_wikipedia_text.py jawiki-20250920-pages-articles1.xml 10000")
        sys.exit(1)

    xml_file = Path(sys.argv[1])
    if not xml_file.exists():
        print(f"❌ File not found: {xml_file}")
        sys.exit(1)

    max_articles = int(sys.argv[2]) if len(sys.argv) > 2 else None

    output_file = Path('wiki_combined.txt')

    extract_text_from_xml(xml_file, output_file, max_articles)


if __name__ == '__main__':
    main()
