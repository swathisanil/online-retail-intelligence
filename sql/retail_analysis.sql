-- Create database
CREATE DATABASE online_retail;                                                           -- create database
USE online_retail;                                                                       -- switch database

-- Create retail table structure
CREATE TABLE retail (                                                                    -- main fact table
    Invoice_no       VARCHAR(20),                                                       -- invoice number
    Stock_code       VARCHAR(20),                                                       -- product code
    Description      VARCHAR(255),                                                      -- product name
    Quantity         INT,                                                               -- quantity sold
    Invoice_date     DATETIME,                                                          -- transaction date
    Unit_price      DECIMAL(10,2),                                                     -- unit price
    Total_revenue   DECIMAL(12,2),                                                     -- revenue per row
    Customer_segment VARCHAR(20),                                                      -- customer type
    Customer_ID      VARCHAR(20),                                                      -- customer id
    Country          VARCHAR(100),                                                     -- country
    Month_name       VARCHAR(20),                                                      -- month name
    Year             INT,                                                              -- year
    Month_short      VARCHAR(5)                                                        -- short month
);

-- Load cleaned CSV into table
LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/online_retail_cleaned.csv'
INTO TABLE retail                                                                        -- target table
FIELDS TERMINATED BY ','                                                                -- csv separator
ENCLOSED BY '"'                                                                         -- text qualifier
LINES TERMINATED BY '\r\n'                                                              -- row separator
IGNORE 1 ROWS                                                                           -- skip header
(Invoice_no, Stock_code, Description, Quantity, Invoice_date, Unit_price,
 @Total_revenue, Customer_segment, @Customer_ID, Country, Month_name, Year, Month_short)
SET
    Total_revenue = NULLIF(REPLACE(@Total_revenue, ',', ''), ''),                      -- clean revenue
    Customer_ID = NULLIF(@Customer_ID, '');                                            -- clean customer id

-- Basic data quality check
SELECT                                                                                -- revenue summary
    SUM(Total_revenue) AS total_revenue,                                               -- total revenue
    COUNT(*) AS total_rows,                                                            -- total records
    AVG(Total_revenue) AS avg_revenue,                                                 -- average value
    MAX(Total_revenue) AS max_revenue,                                                 -- highest value
    MIN(Total_revenue) AS min_revenue                                                  -- lowest value
FROM retail;

SELECT COUNT(*) AS total_rows FROM retail;                                              -- row verification

-- Monthly revenue and growth trend
SELECT
    DATE_FORMAT(Invoice_date, '%Y-%m') AS Month,                                        -- month
    SUM(Total_revenue) AS Revenue,                                                     -- monthly revenue
    ROUND(SUM(Total_revenue) - LAG(SUM(Total_revenue)) 
    OVER (ORDER BY DATE_FORMAT(Invoice_date, '%Y-%m')), 2) AS MoM_Change,              -- change
    CONCAT(ROUND(
        (SUM(Total_revenue) - LAG(SUM(Total_revenue)) 
        OVER (ORDER BY DATE_FORMAT(Invoice_date, '%Y-%m')))
        / LAG(SUM(Total_revenue)) OVER (ORDER BY DATE_FORMAT(Invoice_date, '%Y-%m')) * 100, 1),
    '%') AS MoM_Growth_Pct                                                             -- growth %
FROM retail
GROUP BY Month
ORDER BY Month;

-- Top customers by revenue
SELECT
    Customer_ID,                                                                        -- customer id
    Country,                                                                            -- country
    SUM(Total_revenue) AS Total_Spend,                                                 -- total spend
    COUNT(DISTINCT Invoice_no) AS Total_Orders,                                         -- orders
    RANK() OVER (ORDER BY SUM(Total_revenue) DESC) AS Revenue_Rank                     -- ranking
FROM retail
WHERE Customer_ID IS NOT NULL
GROUP BY Customer_ID, Country
ORDER BY Revenue_Rank
LIMIT 10;

-- Revenue contribution by country
SELECT
    Country,                                                                            -- country
    SUM(Total_revenue) AS Revenue,                                                     -- revenue
    RANK() OVER (ORDER BY SUM(Total_revenue) DESC) AS Revenue_Rank,                    -- rank
    CONCAT(ROUND(
        SUM(SUM(Total_revenue)) OVER (ORDER BY SUM(Total_revenue) DESC)
        / SUM(SUM(Total_revenue)) OVER () * 100, 1), '%') AS Cumulative_Pct           -- cumulative %
FROM retail
GROUP BY Country;

-- Repeat customer analysis
SELECT
    Country,                                                                            -- country
    COUNT(DISTINCT Customer_ID) AS Total_Customers,                                    -- customers
    COUNT(DISTINCT CASE WHEN order_count >= 2 THEN Customer_ID END) AS Repeat_Customers,-- repeat
    CONCAT(ROUND(
        COUNT(DISTINCT CASE WHEN order_count >= 2 THEN Customer_ID END)
        / COUNT(DISTINCT Customer_ID) * 100, 1), '%') AS Repeat_Rate                 -- rate
FROM (
    SELECT Customer_ID, Country, COUNT(DISTINCT Invoice_no) AS order_count
    FROM retail
    WHERE Customer_ID IS NOT NULL
    GROUP BY Customer_ID, Country
) t
GROUP BY Country;

-- Top products by revenue
SELECT
    Description,                                                                        -- product
    SUM(Total_revenue) AS Revenue,                                                     -- revenue
    SUM(Quantity) AS Units_Sold                                                        -- units
FROM retail
WHERE Customer_ID IS NOT NULL
  AND Description NOT IN ('POSTAGE','MANUAL','BANK CHARGES','CRUK Commission','Discount','DOTCOM POSTAGE','AMAZON FEE')
GROUP BY Description
ORDER BY Revenue DESC
LIMIT 10;

-- Customer order frequency
SELECT
    order_count AS Orders_Placed,                                                      -- frequency
    COUNT(DISTINCT Customer_ID) AS Customers,                                          -- customers
    CONCAT(ROUND(COUNT(DISTINCT Customer_ID) 
    / SUM(COUNT(DISTINCT Customer_ID)) OVER () * 100, 1), '%') AS Pct_of_Customers    -- %
FROM (
    SELECT Customer_ID, COUNT(DISTINCT Invoice_no) AS order_count
    FROM retail
    WHERE Customer_ID IS NOT NULL
    GROUP BY Customer_ID
) t
GROUP BY order_count;

-- Average order value by country
SELECT
    Country,                                                                            -- country
    COUNT(DISTINCT Invoice_no) AS Orders,                                              -- orders
    SUM(Total_revenue) AS Total_Revenue,                                               -- revenue
    SUM(Total_revenue)/COUNT(DISTINCT Invoice_no) AS Avg_Order_Value,                 -- AOV
    RANK() OVER (ORDER BY SUM(Total_revenue)/COUNT(DISTINCT Invoice_no) DESC) AS AOV_Rank
FROM retail
WHERE Customer_ID IS NOT NULL
GROUP BY Country;

-- Customer segment performance
SELECT
    Customer_segment,                                                                  -- segment
    COUNT(DISTINCT Invoice_no) AS Orders,                                             -- orders
    SUM(Total_revenue) AS Total_Revenue,                                              -- revenue
    SUM(Total_revenue)/COUNT(DISTINCT Invoice_no) AS Avg_Order_Value,                -- AOV
    CONCAT(ROUND(SUM(Total_revenue)/SUM(SUM(Total_revenue)) OVER () * 100, 1), '%') AS Revenue_Share
FROM retail
GROUP BY Customer_segment;

-- Monthly ranking within each year
SELECT
    Year,                                                                             -- year
    Month_name,                                                                       -- month
    SUM(Total_revenue) AS Revenue,                                                  -- revenue
    RANK() OVER (PARTITION BY Year ORDER BY SUM(Total_revenue) DESC) AS Rank_Within_Year
FROM retail
GROUP BY Year, Month_name;

-- Create view for dashboard
CREATE OR REPLACE VIEW monthly_revenue_summary AS                                    -- reusable view
SELECT
    DATE_FORMAT(Invoice_date, '%Y-%m') AS Month,                                     -- month
    Year,                                                                           -- year
    Month_name,                                                                    -- month name
    SUM(Total_revenue) AS Revenue,                                                 -- revenue
    COUNT(DISTINCT Invoice_no) AS Orders,                                          -- orders
    COUNT(DISTINCT Customer_ID) AS Customers,                                       -- customers
    SUM(Total_revenue)/COUNT(DISTINCT Invoice_no) AS Avg_Order_Value              -- AOV
FROM retail
GROUP BY Month, Year, Month_name;

-- Customer value segmentation
SELECT
    value_tier,                                                                     -- tier
    COUNT(*) AS Customers,                                                         -- customers
    AVG(Total_Spend) AS Avg_Spend,                                                 -- avg
    MIN(Total_Spend) AS Min_Spend,                                                 -- min
    MAX(Total_Spend) AS Max_Spend                                                  -- max
FROM (
    SELECT
        Customer_ID,
        SUM(Total_revenue) AS Total_Spend,
        NTILE(4) OVER (ORDER BY SUM(Total_revenue)) AS value_tier
    FROM retail
    WHERE Customer_ID IS NOT NULL
    GROUP BY Customer_ID
) t
GROUP BY value_tier;

-- Customer retention analysis
SELECT
    Customer_ID,                                                                   -- customer
    MIN(Invoice_date) AS First_Purchase,                                          -- first
    MAX(Invoice_date) AS Last_Purchase,                                           -- last
    COUNT(DISTINCT Invoice_no) AS Total_Orders,                                   -- orders
    DATEDIFF(MAX(Invoice_date), MIN(Invoice_date)) AS Days_Active,               -- lifespan
    SUM(Total_revenue) AS Total_Spend                                             -- spend
FROM retail
WHERE Customer_ID IS NOT NULL
GROUP BY Customer_ID
HAVING Total_Orders >= 2;

-- Order level breakdown
SELECT
    a.Invoice_no,                                                                  -- invoice
    a.Invoice_date,                                                                -- date
    a.Country,                                                                     -- country
    a.Customer_ID,                                                                 -- customer
    b.Line_items,                                                                  -- items
    b.Order_Revenue                                                               -- revenue
FROM retail a
JOIN (
    SELECT
        Invoice_no,
        COUNT(Stock_code) AS Line_items,
        SUM(Total_revenue) AS Order_Revenue
    FROM retail
    GROUP BY Invoice_no
) b ON a.Invoice_no = b.Invoice_no
WHERE a.Customer_ID IS NOT NULL
GROUP BY a.Invoice_no, a.Invoice_date, a.Country, a.Customer_ID, b.Line_items, b.Order_Revenue
ORDER BY b.Order_Revenue DESC
LIMIT 20;