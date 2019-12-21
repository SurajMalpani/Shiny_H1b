#
# This is a Shiny web application for interacting with H1-B Data.
# Author: Suraj Malpani
#

#Loading dependent packages
rqrd_Pkg = c('shiny','data.table','plotly','plyr','tidyverse','wordcloud2')
for(p in rqrd_Pkg){
  if(!require(p,character.only = TRUE)) 
    install.packages(p);
  library(p,character.only = TRUE)
}


# Define UI for application that draws a histogram
ui <- navbarPage("H-1B Visas Analysis",
             tabPanel("All Data",
                  DT::dataTableOutput("table1")), 
             tabPanel("Approvals vs Declines",
                      plotlyOutput("plot1")),
             tabPanel("Departments",
                      fluidRow(
                        helpText("\n
                                  Department wise approvals over the years. \n
                                 You can select which particular deparment you wish to look at by clicking or double clicking on the department name in the plot legends."),
                        plotlyOutput("dept_approval"),
                        helpText("\n
                                 Denial Rate is the percentage of denials over all the applications.
                                 \n As we can see all the deparments are witnessing more denials since 2016."),
                        plotlyOutput("dept_denial"))),
             tabPanel("Geographic",
                      plotlyOutput("states"),
                      plotlyOutput("cities"))
             
)



# Define server logic required to draw a histogram  -----------
server <- function(input, output) {
    
  file_link = "https://www.uscis.gov/sites/default/files/USCIS/Data/Employment-based/H-1B/h1b_datahubexport-All.zip"
  temp <- tempfile()
  download.file(file_link, temp)
  temp_2 = unzip(temp)
  
  #Load the Data 
  Data <- ldply(temp_2, fread)
  columns <-c("Initial Approvals", "Initial Denials", "Continuing Approvals", "Continuing Denials")
  Data[, columns] <- lapply(columns, function(x) as.numeric(Data[[x]]))
  
  # Data Cleaning and transformation
  colnames(Data) <- c("Year","Employer","Initial_Approvals","Initial_Denials"    
                      ,"Continuing_Approvals","Continuing_Denials","NAICS","Tax_ID"              
                      ,"State", "City","ZIP")
  Data[is.na(Data)] <- 0
  
  #cleaning Employer field
  trim <- function (x) gsub("^\\s+|\\s+$", "", x)
  drop_words <- function (x) gsub("INC|LLC|L L C|LLP|CORPORATION|CORP", "", x) 
  Data$Employer <- trim(drop_words(Data$Employer))
  
  Data <- cbind(Data[1:6],apply(Data[7:11],2,as.factor))
  
  ## Top Industries with most approvals/denials -- NAICS ----
  Dept <- read.csv("https://raw.githubusercontent.com/SurajMalpani/Shiny_H1b/master/NAICS.csv")
  colnames(Dept) <- c("NAICS","Dept_Name")
  Dept$NAICS <- as.factor(Dept$NAICS)
  
  c <- left_join(Data, Dept)
  
  Dept_Data <- c %>%
    group_by(Year, Dept_Name) %>%
    summarize(Approvals = sum(Initial_Approvals), Denials = sum(Initial_Denials),
              C_Approvals = sum(Continuing_Approvals), C_Denials = sum(Continuing_Denials)) %>%
    mutate(Denial_Rate = round(Denials/(Approvals+Denials)*100, digits=2))
  
  #Preparing cities data
  cities <- Data %>%
    filter(Year > 2017) %>%
    group_by(City) %>%
    summarize(Approvals = sum(Initial_Approvals), Denials = sum(Initial_Denials),
              C_Approvals = sum(Continuing_Approvals), C_Denials = sum(Continuing_Denials)) %>%
    arrange(desc(Approvals)) %>%
    top_n(50, Approvals)
  
  coords_cities <- read.csv("https://raw.githubusercontent.com/SurajMalpani/Shiny_H1b/master/City_Coordinates.csv")
  cities <- left_join(cities, coords_cities, by="City")
  
  
  #Creating all Output objects -------
  output$table1 <- DT::renderDataTable({
    Data
  }, filter='top', 
  options = list(pageLength = 10, scrollX=TRUE, autoWidth = TRUE, columnDefs = list(list(width = '200px', targets = 2))))
  
  #plotly chart of total approvals and denials:
  output$plot1 <- renderPlotly({
  Data %>%
      group_by(Year) %>%
      summarize(Approvals = sum(Initial_Approvals), Denials = sum(Initial_Denials),
                C_Approvals = sum(Continuing_Approvals), C_Denials = sum(Continuing_Denials)) %>%
    plot_ly(x = ~Year, y = ~Approvals, type = "scatter", mode = "lines", color = I('dark green'), name = "Approvals") %>%
      add_trace(x = ~Year, y = ~Denials, type = "scatter", mode = "lines", color = I('red'), name = "Denials") %>%
      layout(title = "H-1B Visas by Year",
           xaxis = list(title = "Year"),
           yaxis = list(title = "Count"))
  
  })
  
  
  #Which Industries/departments are doing well ---
  #No. of approvals plot
  output$dept_approval <- renderPlotly({
  plot_ly(Dept_Data, x = ~Year, y=~Approvals, color =~Dept_Name, type='scatter', mode = 'line') %>%
    layout(title = "H-1B Visas Approvals by Department",
           xaxis = list(title = "Year"),
           yaxis = list(title = "Count"))
  })
  
  #Denial rate plot
  output$dept_denial <- renderPlotly({
    plot_ly(Dept_Data, x = ~Year, y=~Denial_Rate, color =~Dept_Name, type='scatter', mode = 'line') %>%
    layout(title = "H-1B Visas Denial Rate by Department",
           xaxis = list(title = "Year"),
           yaxis = list(range = c(0,50), title = "% Denials"))
  })
  
  #Geographic analysis --- 
  #Plotting top 10 states with max approvals in last 2 years using plotly
  output$states <- renderPlotly({
    Data %>%
      filter(Year > 2017) %>%
      group_by(State) %>%
      summarize(Approvals = sum(Initial_Approvals), Denials = sum(Initial_Denials),
                C_Approvals = sum(Continuing_Approvals), C_Denials = sum(Continuing_Denials)) %>%
      arrange(desc(Approvals)) %>%
      top_n(10, Approvals) %>%
      plot_ly(x= ~(factor(State, levels=unique(State))[order(Approvals, decreasing = TRUE)]), 
              y=~Approvals, type='bar') %>%
      layout(title = "Top 10 States with highest Approvals in 2018, 2019",
             xaxis = list(title = "State"),
             yaxis = list(title = "Approvals"))
  })
  
  # geo styling for plot_geo
  g <- list(
    scope = 'usa',
    showland = TRUE,
    landcolor = toRGB('light gray'),
    projection = list(type = 'albers usa'),
    showlakes = TRUE,
    lakecolor = toRGB('white')
  )
  
  # Plot of top cities
  output$cities <- renderPlotly({
  plot_geo(cities, lat = ~lat, lon = ~lon, color = ~Approvals, size = ~Approvals) %>%
    add_markers(hovertext = ~(paste("City:", City, "\nNo. of Approvals:", Approvals))) %>%
    layout(title = 'Top cities with H-1B Approvals in 2018 & 2019', geo=g)
  })
  


}


# Run the application 
shinyApp(ui = ui, server = server)
