#
#            Nim's Runtime Library
#        (c) Copyright 2022 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## Nim `idx`:idx: file format related definitions.

import std/[strutils, syncio, hashes]
from std/os import splitFile

type
  IndexEntryKind* = enum ## discriminator tag
    ieMarkupTitle = "markupTitle"
                           ## RST/Markdown title, text in `keyword` +
                           ## HTML text in `linkTitle`
    ieNimTitle = "nimTitle"
                           ## Nim title
    ieHeading = "heading"  ## RST/Markdown markup heading, escaped
    ieIdxRole = "idx"      ## RST :idx: definition, escaped
    ieNim = "nim"          ## Nim symbol, unescaped
    ieNimGroup = "nimgrp"  ## Nim overload group, unescaped
  IndexEntry* = object
    kind*: IndexEntryKind  ## 0.
    keyword*: string       ## 1.
    link*: string          ## 2.
    linkTitle*: string     ## 3. contains a prettier text for the href
    linkDesc*: string      ## 4. the title attribute of the final href
    line*: int             ## 5.
    module*: string        ## origin file, NOT a field in ``.idx`` file
    aux*: string           ## auxuliary field, NOT a field in ``.idx`` file

proc isDocumentationTitle*(hyperlink: string): bool =
  ## Returns true if the hyperlink is actually a documentation title.
  ##
  ## Documentation titles lack the hash. See `mergeIndexes()
  ## <#mergeIndexes,string>`_ for a more detailed explanation.
  result = hyperlink.find('#') < 0

proc `$`*(e: IndexEntry): string =
  """("$1", "$2", "$3", "$4", $5)""" % [
      e.keyword, e.link, e.linkTitle, e.linkDesc, $e.line]

proc quoteIndexColumn(text: string): string =
  ## Returns a safe version of `text` for serialization to the ``.idx`` file.
  ##
  ## The returned version can be put without worries in a line based tab
  ## separated column text file. The following character sequence replacements
  ## will be performed for that goal:
  ##
  ## * ``"\\"`` => ``"\\\\"``
  ## * ``"\n"`` => ``"\\n"``
  ## * ``"\t"`` => ``"\\t"``
  result = newStringOfCap(text.len + 3)
  for c in text:
    case c
    of '\\': result.add "\\"
    of '\L': result.add "\\n"
    of '\C': discard
    of '\t': result.add "\\t"
    else: result.add c

proc unquoteIndexColumn*(text: string): string =
  ## Returns the unquoted version generated by ``quoteIndexColumn``.
  result = text.multiReplace(("\\t", "\t"), ("\\n", "\n"), ("\\\\", "\\"))

proc formatIndexEntry*(kind: IndexEntryKind; htmlFile, id, term, linkTitle,
                       linkDesc: string, line: int):
                      tuple[entry: string, isTitle: bool] =
  result.entry = $kind
  result.entry.add('\t')
  result.entry.add term
  result.entry.add('\t')
  result.entry.add(htmlFile)
  if id.len > 0:
    result.entry.add('#')
    result.entry.add(id)
    result.isTitle = false
  else:
    result.isTitle = true
  result.entry.add('\t' & linkTitle.quoteIndexColumn)
  result.entry.add('\t' & linkDesc.quoteIndexColumn)
  result.entry.add('\t' & $line)
  result.entry.add("\n")

proc parseIndexEntryKind(s: string): IndexEntryKind =
  result = case s:
    of "nim": ieNim
    of "nimgrp": ieNimGroup
    of "heading": ieHeading
    of "idx": ieIdxRole
    of "nimTitle": ieNimTitle
    of "markupTitle": ieMarkupTitle
    else: raise newException(ValueError, "unknown index entry value $1" % [s])

proc parseIdxFile*(path: string):
    tuple[fileEntries: seq[IndexEntry], title: IndexEntry] =
  var
    f = 0
  newSeq(result.fileEntries, 500)
  setLen(result.fileEntries, 0)
  let (_, base, _) = path.splitFile
  for line in lines(path):
    let s = line.find('\t')
    if s < 0: continue
    setLen(result.fileEntries, f+1)
    let cols = line.split('\t')
    result.fileEntries[f].kind = parseIndexEntryKind(cols[0])
    result.fileEntries[f].keyword = cols[1]
    result.fileEntries[f].link = cols[2]
    if result.fileEntries[f].kind == ieIdxRole:
      result.fileEntries[f].module = base
    else:
      if result.title.keyword.len == 0:
        result.fileEntries[f].module = base
      else:
        result.fileEntries[f].module = result.title.keyword

    result.fileEntries[f].linkTitle = cols[3].unquoteIndexColumn
    result.fileEntries[f].linkDesc = cols[4].unquoteIndexColumn
    result.fileEntries[f].line = parseInt(cols[5])

    if result.fileEntries[f].kind in {ieNimTitle, ieMarkupTitle}:
      result.title = result.fileEntries[f]
    inc f

proc cmp*(a, b: IndexEntry): int =
  ## Sorts two ``IndexEntry`` first by `keyword` field, then by `link`.
  result = cmpIgnoreStyle(a.keyword, b.keyword)
  if result == 0:
    result = cmpIgnoreStyle(a.link, b.link)

proc hash*(x: IndexEntry): Hash =
  ## Returns the hash for the combined fields of the type.
  ##
  ## The hash is computed as the chained hash of the individual string hashes.
  result = x.keyword.hash !& x.link.hash
  result = result !& x.linkTitle.hash
  result = result !& x.linkDesc.hash
  result = !$result
