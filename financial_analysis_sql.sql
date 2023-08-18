
-- Find financial details of mentioned customer for given fiscal year and quarter --  

SELECT 
	s.date,s.product_code,
    p.product, p.variant, s.sold_quantity, 
    ROUND(g.gross_price,2) AS gross_price,	
    ROUND(g.gross_price*s.sold_quantity,2) AS gross_price_total 	
FROM fact_sales_monthly s
JOIN dim_product p
ON p.product_code=s.product_code
JOIN fact_gross_price g
ON g.product_code=s.product_code AND g.fiscal_year=get_fiscal_year(s.date)
WHERE 
	customer_code = 90002002 AND
    get_fiscal_year(date) = 2021 AND
    get_fiscal_quarter(date) = "Q4"
ORDER BY date ASC
LIMIT 1000000;

-- Calculate gross price for mentioned customer for given fiscal year --  

SELECT get_fiscal_year(s.date) AS fiscal_year, SUM(ROUND((s.sold_quantity*g.gross_price),2)) as gross_price_total 
FROM fact_sales_monthly s 
JOIN fact_gross_price g
ON g.product_code=s.product_code AND
   g.fiscal_year=get_fiscal_year(s.date)
WHERE s.customer_code=90002002
GROUP BY get_fiscal_year(s.date)
ORDER BY fiscal_year ASC;

-- Creating view for pre-invoice deductions to find net invoice sale --  

CREATE  VIEW `sales_preinv_discount` AS
SELECT 
		s.date, 
		s.fiscal_year,
		s.customer_code,
		c.market,
		s.product_code, 
		p.product, 
		p.variant, 
		s.sold_quantity, 
		g.gross_price as gross_price_per_item,
		ROUND(s.sold_quantity*g.gross_price,2) as gross_price_total,
		pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_customer c 
	ON s.customer_code = c.customer_code
JOIN dim_product p
		ON s.product_code=p.product_code
JOIN fact_gross_price g
		ON g.fiscal_year=s.fiscal_year
		AND g.product_code=s.product_code
JOIN fact_pre_invoice_deductions as pre
		ON pre.customer_code = s.customer_code AND
		pre.fiscal_year=s.fiscal_year;
        
-- net_invoice_sales using the above created view 'sales_preinv_discount'

SELECT 
		*,
		(gross_price_total-pre_invoice_discount_pct*gross_price_total) as net_invoice_sales
FROM sales_preinv_discount;

-- Create a view for post invoice deductions: `sales_postinv_discount`

CREATE VIEW `sales_postinv_discount` AS
SELECT 
		s.date, s.fiscal_year,
		s.customer_code, s.market,
		s.product_code, s.product, s.variant,
		s.sold_quantity, s.gross_price_total,
		s.pre_invoice_discount_pct,
		(s.gross_price_total-s.pre_invoice_discount_pct*s.gross_price_total) as net_invoice_sales,
		(po.discounts_pct+po.other_deductions_pct) as post_invoice_discount_pct
FROM sales_preinv_discount s
JOIN fact_post_invoice_deductions po
	ON po.customer_code = s.customer_code AND
	po.product_code = s.product_code AND
	po.date = s.date;

-- Create a report for net sales
SELECT 
		*, 
		net_invoice_sales*(1-post_invoice_discount_pct) as net_sales
FROM sales_postinv_discount;

-- At last creating the view `net_sales` which including all the previous created view
CREATE VIEW `net_sales` AS
SELECT 
		*, 
		net_invoice_sales*(1-post_invoice_discount_pct) as net_sales
FROM sales_postinv_discount;

-- Get top 5 market by net sales in fiscal year 2021
SELECT 
		market, 
		round(sum(net_sales)/1000000,2) as net_sales_mln
FROM net_sales
where fiscal_year=2021
group by market
order by net_sales_mln desc
limit 5;

-- Find out customer wise net sales percentage contribution 
with cte1 as (
select 
		customer, 
		round(sum(net_sales)/1000000,2) as net_sales_mln
from net_sales s
join dim_customer c
		on s.customer_code=c.customer_code
where s.fiscal_year=2021
group by customer)
select 
	*,
	net_sales_mln*100/sum(net_sales_mln) over() as pct_net_sales
from cte1
order by net_sales_mln desc;


-- Find customer wise net sales distibution per region for FY 2021
with cte1 as (
select 
	c.customer,
	c.region,
	round(sum(net_sales)/1000000,2) as net_sales_mln
	from gdb0041.net_sales n
	join dim_customer c
		on n.customer_code=c.customer_code
where fiscal_year=2021
group by c.customer, c.region)
select
	 *,
	 net_sales_mln*100/sum(net_sales_mln) over (partition by region) as pct_share_region
from cte1
order by region, pct_share_region desc;

-- Find out top 3 products from each division by total quantity sold in a given year
with cte1 as 
(select
			 p.division,
			 p.product,
			 sum(sold_quantity) as total_qty
		from fact_sales_monthly s
		join dim_product p
			  on p.product_code=s.product_code
		where fiscal_year=2021
		group by p.product),
   cte2 as 
	(select 
			 *,
			 dense_rank() over (partition by division order by total_qty desc) as drnk
		from cte1)
select * from cte2 where drnk<=3;



