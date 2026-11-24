#' Draw a Data Frame as a Table on Its Own PDF Page
#'
#' @description Starts a new page on the open graphics device and draws a table with
#'   base graphics: a title, a shaded header row, one row per record and an optional
#'   footnote. Column widths follow the longest entry in each column, up to
#'   `max_chars`; longer text wraps onto extra lines within its row. Text shrinks to
#'   fit when the table is wide or long.
#' @param df data.frame. The table; every column is shown as text.
#' @param title character. Title printed above the table.
#' @param footnote character or NULL. Text printed below the table, wrapped to the
#'   page width.
#' @param max_chars integer. Widest a column may be, in characters, before wrapping.
#' @return NULL, invisibly drawn on the current device. Hard `stop()`s if `df` has no rows.
#' @author Zachary Amir
plot_table_page <- function(df, title, footnote = NULL, max_chars = 40) {
  # if there is nothing to draw,
  if (nrow(df) == 0) {
    # stop because an empty page helps nobody
    stop("plot_table_page got an empty table for '", title, "'.\n",
         "Check the step that built it.")
  } # end empty check

  ## turn every cell into text, wrapped to the column's width
  # all cells as text, with missing values blank
  txt <- as.data.frame(lapply(df, function(v) ifelse(is.na(v), "", as.character(v))),
                       stringsAsFactors = FALSE)
  # each column's width in characters: its longest entry or header, capped
  widths <- vapply(seq_along(txt), function(j) {
    min(max_chars, max(nchar(c(names(df)[j], txt[[j]]))))
  }, numeric(1))
  # wrap a piece of text to a width and keep its lines
  wrap <- function(s, w) {
    lines <- strwrap(s, width = w)
    if (length(lines) == 0) "" else lines
  } # end wrap helper
  # the header, wrapped
  head_lines <- lapply(seq_along(txt), function(j) wrap(names(df)[j], widths[j]))
  # every cell, wrapped, as a list of rows each holding a list of cells
  body_lines <- lapply(seq_len(nrow(txt)), function(i) {
    lapply(seq_along(txt), function(j) wrap(txt[i, j], widths[j]))
  }) # end per row
  # lines each row needs (its tallest cell)
  head_h <- max(lengths(head_lines))
  row_h <- vapply(body_lines, function(r) max(lengths(r)), numeric(1))

  ## set up the page in units of characters and lines
  # a gap of two characters between columns
  col_x <- cumsum(c(0, widths + 2))
  total_w <- col_x[length(col_x)]
  # total lines: title, gap, header, rows, gap, footnote
  foot_lines <- if (is.null(footnote)) character(0) else strwrap(footnote, width = total_w)
  total_h <- 3 + head_h + sum(row_h) + 1 + length(foot_lines)
  # a blank page with no margins
  graphics::par(mar = c(1, 1, 1, 1))
  graphics::plot.new()
  # one x unit per character and one y unit per line, with y counting down the page
  graphics::plot.window(xlim = c(0, total_w), ylim = c(total_h, 0), xaxs = "i", yaxs = "i")
  ## shrink text so an average character fits one x unit and a line fits one y unit
  # (a lower-case 'n' is about the average width of proportional text)
  cex <- min(1.1, 1 / graphics::strwidth("n", cex = 1),
             0.6 / abs(graphics::strheight("M", cex = 1)))

  ## draw the title, header and rows
  graphics::text(0, 0.5, title, adj = c(0, 0.5), font = 2, cex = cex * 1.2)
  # current line, below the title
  y <- 2
  # shade the header band
  graphics::rect(-0.5, y - 0.1, total_w, y + head_h + 0.1, col = "grey88", border = NA)
  # write each header cell, one line at a time
  for (j in seq_along(head_lines)) {
    graphics::text(col_x[j], y + seq_along(head_lines[[j]]) - 0.5, head_lines[[j]],
                   adj = c(0, 0.5), font = 2, cex = cex)
  } # end per header cell
  y <- y + head_h
  # for each row,
  for (i in seq_along(body_lines)) {
    # write each cell, one line at a time
    for (j in seq_along(body_lines[[i]])) {
      graphics::text(col_x[j], y + seq_along(body_lines[[i]][[j]]) - 0.5, body_lines[[i]][[j]],
                     adj = c(0, 0.5), cex = cex)
    } # end per cell
    # rule a faint line under the row
    y <- y + row_h[i]
    graphics::segments(-0.5, y, total_w, y, col = "grey80")
  } # end per row

  ## the footnote, if any
  if (length(foot_lines) > 0) {
    graphics::text(0, y + 1 + seq_along(foot_lines) - 0.5, foot_lines, adj = c(0, 0.5),
                   cex = cex * 0.9, col = "grey25")
  } # end footnote condition

  return(invisible(NULL))
} # end function
