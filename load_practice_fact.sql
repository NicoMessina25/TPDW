SELECT *
		FROM dblink(
			'host=localhost user=postgres password=1234 dbname=OLTP',
			'SELECT 
				bod.benefitorder,
				bod.benefitoderdetail,
				bod.datetime,
				hpc.patient,
				
		 	FROM benefitorderdetail bod
			JOIN benefitoder bo
			LEFT JOIN healtpatientcoverage hpc
		 	WHERE bod.benefitorderdetailstate IN (3,4,5,7,8,10,11) -- (Facturado, Rechazado, Refacturado, Aceptado, Liquidado, Pagado, Debitado)'
		) AS t(
			practice_id bigint,
			order_id bigint,
			first_name character varying, 
			last_name character varying,
			gender character varying,
			site bigint
		)