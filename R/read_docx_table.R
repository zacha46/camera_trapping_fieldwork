#' Read a Table From a Word Document
#'
#' @description Pulls one table out of a `.docx` file and returns it as a data frame of
#'   text, taking the first row as the column names. A `.docx` is a zip archive whose
#'   text lives in `word/document.xml`; each table is a `w:tbl` element, each row a
#'   `w:tr` and each cell a `w:tc`. Cell text is trimmed of surrounding spaces.
#' @param path character. Path to the `.docx` file.
#' @param table integer. Which table to read, counting from 1 in document order.
#' @return data.frame of character columns, one row per table row after the header.
#'   Hard `stop()`s if the file is missing or holds fewer tables than asked for.
#' @author Zachary Amir
read_docx_table <- function(path, table = 1) {
  # if the file is not there,
  if (!file.exists(path)) {
    # stop and say where it was expected
    stop("read_docx_table found no file at ", path,
         "\nCheck the path, and that the document sits in the campaign's data/raw/ folder.")
  } # end file check

  ## open the document's main XML part without unzipping it to disk
  con <- unz(path, "word/document.xml")
  # read it as one XML document
  doc <- xml2::read_xml(con)
  # Word's XML namespace, which every element name carries
  ns <- xml2::xml_ns(doc)

  # grab every table in the document
  tables <- xml2::xml_find_all(doc, "//w:tbl", ns)
  # if the requested table does not exist,
  if (length(tables) < table) {
    # stop and say how many there are
    stop(sprintf("read_docx_table found %d table(s) in %s but table %d was asked for.",
                 length(tables), basename(path), table),
         "\nOpen the document and count its tables.")
  } # end table count check

  ## turn each row into a vector of cell text
  rows <- xml2::xml_find_all(tables[[table]], "./w:tr", ns)
  cells <- lapply(rows, function(r) {
    # the text of each cell, with all its runs joined together
    trimws(xml2::xml_text(xml2::xml_find_all(r, "./w:tc", ns)))
  }) # end per row

  # the first row holds the column names
  header <- cells[[1]]
  # stack the remaining rows into a matrix of text, one row per table row
  body <- do.call(rbind, cells[-1])
  # turn it into a data frame named by the header
  out <- data.frame(body, stringsAsFactors = FALSE)
  names(out) <- header

  return(out)
} # end function
