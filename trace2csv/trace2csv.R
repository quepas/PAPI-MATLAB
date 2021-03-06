library(dplyr)
library(tidyr)
library(stringr)

trace2csv <- function(trace_path, csv_path, explicit_time = F, start_from_in_process = 1) {
  trace_id_val <- 1
  csv_has_header <- F
  omit_trace <- F
  
  df_add_perf_events <- function(str_line) {
    perf_events <- str_split(str_line, ":", n = 2)[[1]][2]
    header <- str_split(perf_events, ",")[[1]]
    raw_subtrace <- matrix(ncol = length(header), nrow = 0)
    colnames(raw_subtrace) <- header
    raw_subtrace
  }
  
  df_fill_subtrace <- function(str_line, raw_subtrace) {
    values <- as.numeric(str_split(str_line, ",")[[1]])
    rbind(raw_subtrace, values)
  }
  df_finish_subtrace <- function(raw_subtrace, trace_id_val, subtrace, csv_file, csv_has_header) {
    # add time column
    raw_subtrace <- as.data.frame(raw_subtrace)
    time_series <- raw_subtrace[[1]]
    # Drop first column if not an explicit time
    if (!explicit_time) {
      raw_subtrace <- raw_subtrace[-1]
    }
    # Compute diff for the rest columns
    raw_subtrace <- raw_subtrace %>%
      mutate_all(function(x) {
        x = x - lag(x, default = 0)
      })
    # prepare the df
    df <- raw_subtrace %>%
      mutate(time=time_series) %>%
      group_by(time) %>%
      gather("metrics", "value", -time) %>%
      mutate(
        trace_id = trace_id_val,
        matlab = subtrace[2],
        threads = subtrace[3],
        process = subtrace[4],
        benchmark = subtrace[5],
        version = subtrace[6],
        N = subtrace[7],
        in_process = subtrace[8]
      ) %>%
      select(trace_id,
             matlab,
             threads,
             process,
             benchmark,
             version,
             N,
             in_process,
             metrics,
             time,
             value)
    write.table(df, csv_file, sep=",", quote = F, row.names = F, col.names = !csv_has_header)
  }
  
  is_values_row <- function(str_line) {
    n <- strtoi(substr(str_line, 1, 1))
    !is.na(n)
  }
  
  csv_file  <- file(csv_path, open = "w")
  trace_file  <- file(trace_path, open = "r")
  while (length(str_line <-
                readLines(trace_file, n = 1, warn = FALSE)) > 0) {
    if (!omit_trace && is_values_row(str_line)) {
      raw_subtrace <- df_fill_subtrace(str_line, raw_subtrace) 
    }
    else if (str_starts(str_line, "@trace_start")) {
      subtrace <- str_split(str_line, ":")[[1]]
      omit_trace <- subtrace[8] < start_from_in_process
    }
    else if (!omit_trace && str_starts(str_line, "@perf_events")) {
      raw_subtrace <- df_add_perf_events(str_line)
    }
    else if (!omit_trace && str_starts(str_line, "@trace_end")) {
      df_finish_subtrace(raw_subtrace, trace_id_val, subtrace, csv_file, csv_has_header)
      csv_has_header <- T
      trace_id_val <- trace_id_val + 1
    }
  }
  close(trace_file)
  close(csv_file)
}
