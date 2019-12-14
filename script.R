library(tidyverse)
library(config)
library(httr)
library(glue)
library(listviewer)
library(textclean)

# send GET req via ...
api   <- config::get(config = "api")
addrs <- vector("list", api$length)
cntts <- list()

# seeding initial address
addrs[1] <-
    with(
        api,
        glue::glue(
            "{url}/{topic}/activities?session_id={as.numeric(session_id)}&desktop=False"
        )
    )

# this is to extract text contents
fetch_contents <- function(i) {
    
    r <- httr::GET(addrs[[i]])
    
    # use `listviewer` to explore response
    cntts <<-
        map_chr(content(r)$data, ~ {
            .x %>%
                purrr::pluck("target", "content") %>%
                textclean::replace_html()
        }) %>% append(cntts, .)
    
    # 
    addrs[i + 1] <<- content(r)$paging[['next']]
}

map(1:api$length, fetch_contents)
