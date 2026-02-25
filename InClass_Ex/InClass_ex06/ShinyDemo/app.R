pacman::p_load(shiny, tidyverse)

exam <- read_csv("Exam_data.csv")

# Define UI for application that draws a histogram
ui <- fluidPage(
  titlePanel("Pupils Exam Results Dashboard"),
  sidebarLayout(
    sidebarPanel(
      selectInput(inputId = "variable",
                  label = "Subject:",
                  choices = c("English" = "ENGLISH",
                              "Maths" = "MATHS",
                              "Science" = "SCIENCE"),
                  selected = "ENGLISH"),
      sliderInput(inputId = "bins",
                  label = "Number of Bins",
                  min = 5,
                  max = 20,
                  value= 10)
    ),
    mainPanel(plotOutput("distPlot") )
  )
)

# Define server logic required to draw a histogram
server <- function(input, output){
  output$distPlot <- renderPlot({
    ggplot(data = exam, 
           aes_string(x = input$variable)) + 
      geom_histogram(bins = input$bin,
                     color="black", 
                     fill="light blue")
  })
}

# Run the application 
shinyApp(ui = ui, server = server)