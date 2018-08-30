-- using 1527570634 as a seed to the RNG


select
	cntrycode,
	count(*) as numcust,
	sum(c_acctbal) as totacctbal
from
	(
		select
			substr(c_phone, 1, 2) as cntrycode,
			c_acctbal
		from
			customer
		where
			substr(c_phone, 1, 2) in
				('38', '24', '31', '41', '34', '23', '22')
			and c_acctbal > (
				select
					avg(c_acctbal)
				from
					customer
				where
					c_acctbal > 0.00
					and substr(c_phone, 1, 2) in
						('38', '24', '31', '41', '34', '23', '22')
			)
			and not exists (
				select
					*
				from
					orders
				where
					o_custkey = c_custkey
			)
	) as custsale
group by
	cntrycode
order by
	cntrycode
limit -1;
