library(tidyverse)
library(config)
library(httr)
library(glue)
library(listviewer)
library(textclean)
library(googleLanguageR)
library(igraph)
library(visNetwork)

# Fetching Data -----------------------------------------------------------


# global objects
conf   <- config::get()
addrs <- vector("list", conf$length)
cntts <- list()

# seeding initial address
addrs[1] <-
    with(
        conf,
        glue::glue(
            "{url}/{topic}/activities?session_id={as.numeric(session_id)}&desktop=False"
        )
    )

# this is to extract text contents
fetch_contents <- function(i) {
    
    message("Fetching ", addrs[i])
    r <- httr::GET(addrs[[i]])
    
    # use `listviewer` to explore response
    cntts <<-
        map(content(r)$data, ~ {
            .x %>%
                purrr::pluck("target", "title") %>%
                textclean::replace_html()
        }) %>% append(cntts, .)
    
    # 
    addrs[i + 1] <<- content(r)$paging[['next']]
}

map(1:conf$length, fetch_contents)



# Parsing Entities --------------------------------------------------------


# to GCP NLP API
entities_raw <- map(cntts, ~ gl_nlp(.x, nlp_type = "analyzeEntities", language = conf$language))

# tidy result from api
entities <-
    entities_raw %>%
    map( ~ pluck(.x, "entities", 1)) %>%
    bind_rows(.id = "article") %>%
    filter(salience > conf$salience_cutoff, type != "NUMBER")

# this is our vertices
(
    nodes <- 
        entities %>%
        select(name, type, mid) %>%
        distinct() %>% 
        rownames_to_column(var = "id") %>% 
        rename(label = name) %>% 
        mutate(color = case_when(
            type     == "PERSON" ~ "skyblue",
            type     == "ORGANIZATION" ~ "salmon",
            type     == "LOCATION" ~ "orange",
            TRUE ~ "grey"
        ))
)

# this is our edges
(
    links <- 
        entities %>% 
        select(article, name, type, mid) %>% 
        left_join(nodes, by = c("name" = "label", "type", "mid")) %>% 
        select(id, article) %>% 
        split(.$article) %>% 
        map(~ tidyr::crossing(from = .$id, to = .$id)) %>% 
        map(~ filter(.x, from < to)) %>% 
        bind_rows()
)

# final result
visNetwork(nodes, links, width = conf$width, height = conf$height) %>% 
    visOptions(highlightNearest = TRUE) %>% 
    visHierarchicalLayout(direction = "UD", levelSeparation = 200)

