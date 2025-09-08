CREATE EXTENSION IF NOT EXISTS dblink;

CREATE TABLE IF NOT EXISTS public.health_entity_dim
(
    health_entity_dim_id bigserial NOT NULL,
    health_entity_id bigint NOT NULL,
    commercial_name character varying COLLATE pg_catalog."default" NOT NULL,
    code character varying COLLATE pg_catalog."default" NOT NULL,
    invoicing_type character varying COLLATE pg_catalog."default" NOT NULL,
    plan character varying COLLATE pg_catalog."default" NOT NULL,
    site bigint NOT NULL,
    timestamp_from timestamp with time zone NOT NULL,
    timestamp_to timestamp with time zone NOT NULL,
    plan_id bigint NOT NULL,
    CONSTRAINT health_entity_dim_pkey PRIMARY KEY (health_entity_dim_id)
);

CREATE TABLE IF NOT EXISTS public.nomenclator_dim
(
    nomenclator_dim_id bigserial NOT NULL,
    nomenclator_id bigint NOT NULL,
    description character varying COLLATE pg_catalog."default" NOT NULL,
    code character varying COLLATE pg_catalog."default" NOT NULL,
    chapter character varying COLLATE pg_catalog."default" NOT NULL,
    category character varying COLLATE pg_catalog."default" NOT NULL,
    health_entity character varying COLLATE pg_catalog."default" NOT NULL,
    site bigint NOT NULL,
    timestamp_from timestamp with time zone NOT NULL,
    timestamp_to timestamp with time zone NOT NULL,
    CONSTRAINT nomenclator_dim_pkey PRIMARY KEY (nomenclator_dim_id)
);

CREATE TABLE IF NOT EXISTS public.piece_face_sector_dim
(
    piece_face_sector_id bigserial NOT NULL,
    piece character varying COLLATE pg_catalog."default" NOT NULL,
    faces character varying COLLATE pg_catalog."default" NOT NULL,
    sector character varying COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT piece_face_sector_dim_pkey PRIMARY KEY (piece_face_sector_id)
);

CREATE TABLE IF NOT EXISTS public.patient_dim
(
    patient_dim_id bigserial NOT NULL,
    patient_id bigint NOT NULL,
    first_name character varying COLLATE pg_catalog."default" NOT NULL,
    last_name character varying COLLATE pg_catalog."default" NOT NULL,
    gender character varying COLLATE pg_catalog."default" NOT NULL,
    site bigint NOT NULL,
    CONSTRAINT patient_dim_pkey PRIMARY KEY (patient_dim_id)
);

CREATE TABLE IF NOT EXISTS public.professional_dim
(
    professional_dim_id bigserial NOT NULL,
    professional_id bigint NOT NULL,
    first_name character varying COLLATE pg_catalog."default" NOT NULL,
    last_name character varying COLLATE pg_catalog."default" NOT NULL,
    gender character varying COLLATE pg_catalog."default" NOT NULL,
	license_number character varying COLLATE pg_catalog."default" NOT NULL,
	license_type character varying COLLATE pg_catalog."default" NOT NULL,
    site bigint NOT NULL,
    CONSTRAINT professional_dim_pkey PRIMARY KEY (professional_dim_id)
);

CREATE TABLE IF NOT EXISTS public.time_dim
(
    time_dim_id bigserial NOT NULL,
    date date NOT NULL,
    date_name character varying COLLATE pg_catalog."default" NOT NULL,
    year integer NOT NULL,
    four_month_period integer NOT NULL,
    four_month_period_name character varying COLLATE pg_catalog."default" NOT NULL,
    three_month_period integer NOT NULL,
    three_month_period_name character varying COLLATE pg_catalog."default" NOT NULL,
    two_month_period integer NOT NULL,
    two_month_period_name character varying COLLATE pg_catalog."default" NOT NULL,
    day integer NOT NULL,
    month integer NOT NULL,
    month_name character varying COLLATE pg_catalog."default" NOT NULL,
    weekday integer NOT NULL,
    weekday_name character varying COLLATE pg_catalog."default" NOT NULL,
    season character varying COLLATE pg_catalog."default" NOT NULL,
    type_day character varying COLLATE pg_catalog."default" NOT NULL,
    week_of_the_month integer NOT NULL,
    week_of_the_month_name character varying COLLATE pg_catalog."default" NOT NULL,
    week_of_the_year integer NOT NULL,
    week_of_the_year_name character varying COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT time_dim_pkey PRIMARY KEY (time_dim_id)
);

CREATE OR REPLACE VIEW public.period_dim
 AS
 SELECT min(time_dim_id) AS period_dim_id,
    year,
    month,
    month_name,
    to_char(make_date(year, month, 1)::timestamp with time zone, 'mm/yyyy'::text) AS period_name
   FROM time_dim td
  GROUP BY year, month, month_name
  ORDER BY (min(time_dim_id));

CREATE TABLE IF NOT EXISTS public.age_dim
(
    age_dim_id bigserial NOT NULL,
    age integer NOT NULL,
    range_5 character varying COLLATE pg_catalog."default" NOT NULL,
    range_10 character varying COLLATE pg_catalog."default" NOT NULL,
    life_stage character varying COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT age_dim_pkey PRIMARY KEY (age_dim_id)
);


CREATE OR REPLACE PROCEDURE public.load_health_entity_dim(
	IN p_username character varying,
	IN p_password character varying,
	IN p_dbname character varying)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	timestamp_now timestamp with time zone;
	new_records bigint;
	new_version_records bigint;
BEGIN
	DROP TABLE IF EXISTS temp_health_entity_dim;
	
	EXECUTE format(
		$sql$
		CREATE TEMP TABLE temp_health_entity_dim AS
		SELECT *
		FROM dblink(
			'host=localhost user=%I password=%s dbname=%s',
			'SELECT 
				me.medereentity, 
				COALESCE(me.commercialname,''Desconocido''), 
				COALESCE(me.externalid,''Desconocido''),
				COALESCE(chec.name,''Desconocido''),
				CASE 
			        WHEN upper(trim(translate(hep.name, ''áéíóúÁÉÍÓÚ'', ''aeiouAEIOU''))) = ''UNICO''
			            THEN ''ÚNICO''
			        ELSE hep.name
			    END,
				me.site,
				hep.healthentityplan
			 FROM medereentity me
			 JOIN comphealthentitydata ched ON ched.healthentity = me.medereentity
			 JOIN comphealthentityclass chec ON chec.comphealthentityclass = ched.comphealthentityclass
			 JOIN healthentityplan hep ON hep.healthentity = me.medereentity
			 WHERE me.medereentitytype = 6 AND me.deleted IS NULL'
		) AS t(
			health_entity_id bigint,
			commercial_name character varying, 
			code character varying,
			invoicing_type character varying,
			plan character varying,
			site bigint,
			plan_id bigint
		)
		$sql$,
		p_username, p_password, p_dbname
	);

	timestamp_now := now();

	/* Cierre de versiones anteriores cuando cambian los datos */
	UPDATE health_entity_dim hed
	SET timestamp_to = timestamp_now
	FROM temp_health_entity_dim tmp
	WHERE hed.plan_id = tmp.plan_id
	  AND hed.timestamp_to = '9999-12-31'
	  AND (
	        hed.commercial_name <> tmp.commercial_name OR
	        hed.code <> tmp.code OR
	        hed.invoicing_type <> tmp.invoicing_type OR
	        hed.plan <> tmp.plan
	      );
	
	/* Inserción de nuevas versiones para registros cambiados */
	INSERT INTO health_entity_dim(
	    health_entity_id, commercial_name, code, invoicing_type, plan, site, timestamp_from, timestamp_to, plan_id
	)
	SELECT 
	    tmp.health_entity_id,
	    tmp.commercial_name,
	    tmp.code,
	    tmp.invoicing_type,
	    tmp.plan,
	    tmp.site,
	    timestamp_now AS timestamp_from,
	    '9999-12-31' AS timestamp_to,
		tmp.plan_id
	FROM temp_health_entity_dim tmp
	JOIN health_entity_dim hed 
	    ON hed.plan_id = tmp.plan_id
	   AND hed.timestamp_to = timestamp_now  -- recién cerrado
	WHERE (
	        hed.commercial_name <> tmp.commercial_name OR
	        hed.code <> tmp.code OR
	        hed.invoicing_type <> tmp.invoicing_type OR
	        hed.plan <> tmp.plan
	      );
	GET DIAGNOSTICS new_version_records = ROW_COUNT;

	/* Inserción de nuevos registros */
	INSERT INTO health_entity_dim(health_entity_id, commercial_name, code, invoicing_type, plan, site, timestamp_from, timestamp_to, plan_id)
	SELECT 
		tmp.health_entity_id,
		tmp.commercial_name,
		tmp.code,
		tmp.invoicing_type,
		tmp.plan, 
		tmp.site, 
		'1900-01-01' AS timestamp_from,
		'9999-12-31' AS timestamp_to,
		tmp.plan_id
	FROM temp_health_entity_dim tmp
	WHERE NOT EXISTS (
		SELECT 1
		FROM health_entity_dim
		WHERE health_entity_dim.plan_id = tmp.plan_id
	);
    GET DIAGNOSTICS new_records = ROW_COUNT;

    -- Reporte al operador
	RAISE NOTICE '';
	RAISE NOTICE 'HEALTH_ENTITY_DIM RESULTS:';
    RAISE NOTICE 'Cantidad de registros con nueva versión (SCD2): %', new_version_records;
    RAISE NOTICE 'Cantidad de registros nuevos: %', new_records;
END
$BODY$;


CREATE OR REPLACE PROCEDURE public.load_nomenclator_dim(
	IN p_username character varying,
	IN p_password character varying,
	IN p_dbname character varying)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	timestamp_now timestamp with time zone;
	new_records bigint;
	new_version_records bigint;
	updated_records bigint;
BEGIN
	DROP TABLE IF EXISTS temp_nomenclator_dim;
	
	EXECUTE format(
		$sql$
		CREATE TEMP TABLE temp_nomenclator_dim AS
		SELECT *
		FROM dblink(
			'host=localhost user=%I password=%s dbname=%s',
			'SELECT
				n.nomenclator,
				n.description,
				n.code,
				nc.description,
				COALESCE(cc.name, ''Desconocido''),
				COALESCE(he.commercialname, ''Desconocido''),
				he.site
			FROM nomenclator n
			JOIN nomenclatorchapter nc ON nc.nomenclatorchapter = n.nomenclatorchapter
			JOIN medereentity he ON he.medereentity = n.healthentity AND he.deleted IS NULL
			LEFT JOIN chaptercategoryrelation ccr ON ccr.nomenclatorchapter = n.nomenclatorchapter
			LEFT JOIN chaptercategory cc ON cc.chaptercategory = ccr.chaptercategory
			WHERE n.active = true
			'
		) AS t(
			nomenclator_id bigint,
			description character varying,
			code character varying,
			chapter character varying,
			category character varying,
			health_entity character varying,
			site bigint
		);
		$sql$,
		p_username, p_password, p_dbname
	);

	timestamp_now := now();

	/* Cierre de versiones anteriores cuando cambia el campo health_entity */
	UPDATE nomenclator_dim nd
	SET timestamp_to = timestamp_now
	FROM temp_nomenclator_dim tmp
	WHERE nd.nomenclator_id = tmp.nomenclator_id
	  AND nd.timestamp_to = '9999-12-31'
	  AND (
	        nd.health_entity <> tmp.health_entity
	      );

	/* Actualiza los atributos lentamente cambiantes de tipo 1 */
	UPDATE nomenclator_dim nd
	SET
		description = tmp.description,
		code = tmp.code,
		chapter = tmp.chapter,
		category = tmp.category
	FROM temp_nomenclator_dim tmp
	WHERE tmp.nomenclator_id = nd.nomenclator_id
		AND nd.timestamp_to = '9999-12-31' AND
		(	nd.description <> tmp.description OR
			nd.code <> tmp.code OR
			nd.chapter <> tmp.chapter OR
			nd.category <> tmp.category
		);
	GET DIAGNOSTICS updated_records = ROW_COUNT;

	/* Inserción de nuevas versiones para registros cambiados */
	INSERT INTO nomenclator_dim(
	    nomenclator_id, description, code, chapter, category, health_entity, site, timestamp_from, timestamp_to
	)
	SELECT 
	    tmp.nomenclator_id,
	    tmp.description,
	    tmp.code,
	    tmp.chapter,
	    tmp.category,
		tmp.health_entity,
	    tmp.site,
	    timestamp_now AS timestamp_from,
	    '9999-12-31' AS timestamp_to
	FROM temp_nomenclator_dim tmp
	JOIN nomenclator_dim nd 
	    ON nd.nomenclator_id = tmp.nomenclator_id
	   AND nd.timestamp_to = timestamp_now  -- recién cerrado
	WHERE (
	        nd.health_entity <> tmp.health_entity
	      );
	GET DIAGNOSTICS new_version_records = ROW_COUNT;

	/* Inserción de nuevos registros */
	INSERT INTO nomenclator_dim(
	    nomenclator_id, description, code, chapter, category, health_entity, site, timestamp_from, timestamp_to
	)
	SELECT 
		tmp.nomenclator_id, 
		tmp.description, 
		tmp.code, 
		tmp.chapter, 
		tmp.category, 
		tmp.health_entity, 
		tmp.site,
		'1900-01-01' AS timestamp_from,
		'9999-12-31' AS timestamp_to
	FROM temp_nomenclator_dim tmp
	WHERE NOT EXISTS (
	    SELECT 1
	    FROM nomenclator_dim nd
	    WHERE nd.nomenclator_id = tmp.nomenclator_id
	);
	GET DIAGNOSTICS new_records = ROW_COUNT;

    -- Reporte al operador
	RAISE NOTICE '';
	RAISE NOTICE 'NOMENCLATOR_DIM RESULTS:';
    RAISE NOTICE 'Cantidad de nomencladores actualizados (SCD1): %', updated_records;
    RAISE NOTICE 'Cantidad de nomencladores con nueva versión (SCD2): %', new_version_records;
    RAISE NOTICE 'Cantidad de nomencladores nuevos: %', new_records;
END
$BODY$;


CREATE OR REPLACE PROCEDURE public.load_piece_face_sector_dim(
	)
LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
    v_piece INT;
    v_sector TEXT;
    faces TEXT[] := ARRAY['D','I','L','M','O','P','V'];
    sectors TEXT[] := ARRAY['SA','SD','SI','IA','ID','II'];
	v_count BIGINT;
BEGIN
    -- 1) Verificar si la tabla ya tiene datos; si es así, salir
    SELECT COUNT(*) INTO v_count FROM piece_face_sector_dim;
    IF v_count > 0 THEN
        RAISE NOTICE 'La tabla "piece_face_sector_dim" ya contiene datos. SP abortado.';
        RETURN;
    END IF;

    -- 2) Combinación vacía
    INSERT INTO piece_face_sector_dim(piece, faces, sector)
    VALUES ('Sin pieza', 'Sin caras', 'Sin sector');

    -- 3) Sectores solos
    FOREACH v_sector IN ARRAY sectors
    LOOP
        INSERT INTO piece_face_sector_dim(piece, faces, sector)
        VALUES ('Sin pieza', 'Sin caras', v_sector);
    END LOOP;

    -- 4) Piezas sin caras ni sector
    FOR v_piece IN
        SELECT val FROM (VALUES
            (11),(12),(13),(14),(15),(16),(17),(18),
            (21),(22),(23),(24),(25),(26),(27),(28),
            (31),(32),(33),(34),(35),(36),(37),(38),
            (41),(42),(43),(44),(45),(46),(47),(48),
            (51),(52),(53),(54),(55),(61),(62),(63),
            (64),(65),(71),(72),(73),(74),(75),
            (81),(82),(83),(84),(85),(99)
        ) AS p(val)
    LOOP
        INSERT INTO piece_face_sector_dim(piece, faces, sector)
        VALUES (v_piece, 'Sin caras', 'Sin sector');
    END LOOP;

    -- 5) Piezas con todas las combinaciones posibles de caras
    FOR v_piece IN
        SELECT val FROM (VALUES
            (11),(12),(13),(14),(15),(16),(17),(18),
            (21),(22),(23),(24),(25),(26),(27),(28),
            (31),(32),(33),(34),(35),(36),(37),(38),
            (41),(42),(43),(44),(45),(46),(47),(48),
            (51),(52),(53),(54),(55),(61),(62),(63),
            (64),(65),(71),(72),(73),(74),(75),
            (81),(82),(83),(84),(85),(99)
        ) AS p(val)
    LOOP
        INSERT INTO piece_face_sector_dim(piece, faces, sector)
        WITH RECURSIVE combinations(combo, last_face) AS (
            -- Caso base: Cada cara como una combinación de un solo elemento.
            SELECT ARRAY[f], f
            FROM unnest(faces) AS t(f)

            UNION ALL

            -- Paso recursivo: A cada combinación existente, le agregamos una nueva cara
            -- que sea alfabéticamente MAYOR a la última cara de la combinación.
            SELECT combo || f, f
            FROM combinations, unnest(faces) AS t(f)
            WHERE f > last_face
        )
        SELECT v_piece, array_to_string(combo, ''), 'Sin sector'
        FROM combinations;
    END LOOP;
END;
$BODY$;



CREATE OR REPLACE PROCEDURE public.load_patient_dim(
	IN p_username character varying, 
	IN p_password character varying, 
	IN p_dbname character varying)
	
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	new_records bigint;
	updated_records bigint;
BEGIN
	DROP TABLE IF EXISTS temp_patient_dim;

	EXECUTE format(
		$sql$
		CREATE TEMP TABLE temp_patient_dim AS
		SELECT *
		FROM dblink(
			'host=localhost user=%I password=%s dbname=%s',
			'SELECT 
				me.medereentity, 
				COALESCE(me.firstname, ''Desconocido''), 
				COALESCE(me.lastname, ''Desconocido''),
				COALESCE(me.gender, ''Desconocido''),
				me.site
		 	FROM medereentity me
		 	WHERE me.medereentitytype = 2 AND me.deleted IS NULL'
		) AS t(
			patient_id bigint,
			first_name character varying, 
			last_name character varying,
			gender character varying,
			site bigint
		)
		$sql$,
		p_username, p_password, p_dbname
	);

	/* Actualiza los atributos lentamente cambiantes de tipo 1 */
	UPDATE patient_dim pd
	SET
		first_name = tpd.first_name,
		last_name = tpd.last_name,
		gender = tpd.gender
	FROM temp_patient_dim tpd
	WHERE tpd.patient_id = pd.patient_id AND
		( 	pd.first_name <> tpd.first_name OR
			pd.last_name <> tpd.last_name OR
			pd.gender <> tpd.gender
		);
	GET DIAGNOSTICS updated_records = ROW_COUNT;

	/* Inserción de nuevas versiones para registros cambiados */
	INSERT INTO patient_dim(patient_id, first_name, last_name, gender, site)
	SELECT
		tpd.patient_id,
		tpd.first_name,
		tpd.last_name,
		tpd.gender,
		tpd.site
	FROM temp_patient_dim tpd
	WHERE NOT EXISTS (
		SELECT 1 
		FROM patient_dim pd 
		WHERE pd.patient_id = tpd.patient_id
	);
	GET DIAGNOSTICS new_records = ROW_COUNT;

	-- Reporte al operador
	RAISE NOTICE '';
	RAISE NOTICE 'PATIENT_DIM RESULTS:';
	RAISE NOTICE 'Cantidad de pacientes actualizados (SCD1): %', updated_records;
    RAISE NOTICE 'Cantidad de pacientes nuevos: %', new_records;
END
$BODY$;



CREATE OR REPLACE PROCEDURE public.load_professional_dim(
	IN p_username character varying, 
	IN p_password character varying, 
	IN p_dbname character varying)
	
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	new_records bigint;
	updated_records bigint;
BEGIN
	DROP TABLE IF EXISTS temp_professional_dim;

	EXECUTE format(
		$sql$
		CREATE TEMP TABLE temp_professional_dim AS
		SELECT *
		FROM dblink(
			'host=localhost user=%I password=%s dbname=%s',
			'SELECT 
				me.medereentity, 
				COALESCE(me.firstname, ''Desconocido''), 
				COALESCE(me.lastname, ''Desconocido''), 
				COALESCE(me.gender, ''Desconocido''), 
				me.workerenrollment,
				me.enrollmenttype,
				me.site
		 	FROM medereentity me
		 	WHERE me.medereentitytype = 3 AND me.deleted IS NULL'
		) AS t(
			professional_id bigint,
			first_name character varying, 
			last_name character varying,
			gender character varying,
			license_number character varying,
			license_type character varying,
			site bigint
		)
		$sql$,
		p_username, p_password, p_dbname
	);

	/* Actualiza los atributos lentamente cambiantes de tipo 1 */
	UPDATE professional_dim pd
	SET
		first_name = tpd.first_name,
		last_name = tpd.last_name,
		gender = tpd.gender,
		license_number = tpd.license_number,
		license_type = tpd.license_type
	FROM temp_professional_dim tpd
	WHERE tpd.professional_id = pd.professional_id AND
		(	pd.first_name <> tpd.first_name OR
			pd.last_name <> tpd.last_name OR
			pd.gender <> tpd.gender OR
			pd.license_number <> tpd.license_number OR
			pd.license_type <> tpd.license_type
		);
	GET DIAGNOSTICS updated_records = ROW_COUNT;

	/* Inserción de nuevos registros */
	INSERT INTO professional_dim(professional_id, first_name, last_name, gender, license_number, license_type, site)
	SELECT
		tpd.professional_id,
		tpd.first_name,
		tpd.last_name,
		tpd.gender,
		tpd.license_number,
		tpd.license_type,
		tpd.site
	FROM temp_professional_dim tpd
	WHERE NOT EXISTS (
		SELECT 1 
		FROM professional_dim pd 
		WHERE pd.professional_id = tpd.professional_id
	);
	GET DIAGNOSTICS new_records = ROW_COUNT;

	-- Reporte al operador
	RAISE NOTICE '';
	RAISE NOTICE 'PROFESSIONAL_DIM RESULTS:';
	RAISE NOTICE 'Cantidad de profesionales actualizados (SCD1): %', updated_records;
    RAISE NOTICE 'Cantidad de profesionales nuevos: %', new_records;
END
$BODY$;


CREATE OR REPLACE PROCEDURE load_age_dim()
LANGUAGE 'plpgsql'
AS $$
DECLARE
    v_count INTEGER;
    v_age INTEGER;
BEGIN
    -- Verificar si la tabla ya tiene datos. Si es así, salir.
    SELECT COUNT(*) INTO v_count FROM age_dim;
    IF v_count > 0 THEN
        RAISE NOTICE 'La tabla "age_dim" ya contiene datos. SP abortado.';
        RETURN;
    END IF;

    -- Bucle para insertar edades de 0 a 100
    FOR v_age IN 0..100 LOOP
        INSERT INTO age_dim (
            age,
            range_5,
            range_10,
            life_stage
        ) VALUES (
            v_age,
            CASE
                WHEN v_age BETWEEN 0 AND 4 THEN '0-4'
                WHEN v_age BETWEEN 5 AND 9 THEN '5-9'
                WHEN v_age BETWEEN 10 AND 14 THEN '10-14'
                WHEN v_age BETWEEN 15 AND 19 THEN '15-19'
                WHEN v_age BETWEEN 20 AND 24 THEN '20-24'
                WHEN v_age BETWEEN 25 AND 29 THEN '25-29'
                WHEN v_age BETWEEN 30 AND 34 THEN '30-34'
                WHEN v_age BETWEEN 35 AND 39 THEN '35-39'
                WHEN v_age BETWEEN 40 AND 44 THEN '40-44'
                WHEN v_age BETWEEN 45 AND 49 THEN '45-49'
                WHEN v_age BETWEEN 50 AND 54 THEN '50-54'
                WHEN v_age BETWEEN 55 AND 59 THEN '55-59'
                WHEN v_age BETWEEN 60 AND 64 THEN '60-64'
                WHEN v_age BETWEEN 65 AND 69 THEN '65-69'
                WHEN v_age BETWEEN 70 AND 74 THEN '70-74'
                WHEN v_age BETWEEN 75 AND 79 THEN '75-79'
                WHEN v_age BETWEEN 80 AND 84 THEN '80-84'
                WHEN v_age BETWEEN 85 AND 89 THEN '85-89'
                WHEN v_age BETWEEN 90 AND 94 THEN '90-94'
                WHEN v_age BETWEEN 95 AND 100 THEN '95-100'
                ELSE 'Otros'
            END,
            CASE
                WHEN v_age BETWEEN 0 AND 9 THEN '0-9'
                WHEN v_age BETWEEN 10 AND 19 THEN '10-19'
                WHEN v_age BETWEEN 20 AND 29 THEN '20-29'
                WHEN v_age BETWEEN 30 AND 39 THEN '30-39'
                WHEN v_age BETWEEN 40 AND 49 THEN '40-49'
                WHEN v_age BETWEEN 50 AND 59 THEN '50-59'
                WHEN v_age BETWEEN 60 AND 69 THEN '60-69'
                WHEN v_age BETWEEN 70 AND 79 THEN '70-79'
                WHEN v_age BETWEEN 80 AND 89 THEN '80-89'
                WHEN v_age BETWEEN 90 AND 100 THEN '90-100'
                ELSE 'Otros'
            END,
            CASE
                WHEN v_age BETWEEN 0 AND 12 THEN 'Niñez'
                WHEN v_age BETWEEN 13 AND 19 THEN 'Adolescencia'
                WHEN v_age BETWEEN 20 AND 64 THEN 'Adultez'
                WHEN v_age >= 65 THEN 'Tercera Edad'
                ELSE 'Desconocido'
            END
        );
    END LOOP;
    RAISE NOTICE 'Carga de la dimension "age_dim" completada.';
END;
$$;


CREATE OR REPLACE PROCEDURE load_time_dim()
LANGUAGE plpgsql
AS $$

DECLARE
    v_count INTEGER;
    v_start_date DATE := '2020-01-01';
    v_end_date DATE := '2050-12-31';
    v_current_date DATE;
BEGIN
	-- Configurar el idioma para obtener nombres en español
    SET lc_time = 'es_ES.UTF-8'; 
	
    -- Verificar si la tabla ya tiene datos. Si es así, salir.
    SELECT COUNT(*) INTO v_count FROM time_dim;
    IF v_count > 0 THEN
        RAISE NOTICE 'La tabla "time_dim" ya contiene datos. SP abortado.';
        RETURN;
    END IF;

    -- Bucle para insertar cada día en el rango de fechas
    v_current_date := v_start_date;
    WHILE v_current_date <= v_end_date LOOP
        INSERT INTO time_dim (
            date,
            date_name,
            year,
            four_month_period,
            four_month_period_name,
            three_month_period,
            three_month_period_name,
            two_month_period,
            two_month_period_name,
            day,
            month,
            month_name,
            weekday,
            weekday_name,
            season,
            type_day,
            week_of_the_month,
            week_of_the_month_name,
            week_of_the_year,
            week_of_the_year_name
        ) VALUES (
            v_current_date,
			TO_CHAR(v_current_date, 'DD/MM/YYYY'),
            EXTRACT(YEAR FROM v_current_date),
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 1 AND 4 THEN 1
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 5 AND 8 THEN 2
                ELSE 3
            END,
			CASE
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 1 AND 4 THEN '1er. Cuatrimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 5 AND 8 THEN '2do. Cuatrimestre'
                ELSE '3er. Cuatrimestre'
            END,
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 1 AND 3 THEN 1
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 4 AND 6 THEN 2
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 7 AND 9 THEN 3
                ELSE 4
            END,
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 1 AND 3 THEN '1er. Trimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 4 AND 6 THEN '2do. Trimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) BETWEEN 7 AND 9 THEN '3er. Trimestre'
                ELSE '4to. Trimestre'
            END,
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) IN (1, 2) THEN 1
                WHEN EXTRACT(MONTH FROM v_current_date) IN (3, 4) THEN 2
                WHEN EXTRACT(MONTH FROM v_current_date) IN (5, 6) THEN 3
                WHEN EXTRACT(MONTH FROM v_current_date) IN (7, 8) THEN 4
                WHEN EXTRACT(MONTH FROM v_current_date) IN (9, 10) THEN 5
                ELSE 6
            END,
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) IN (1, 2) THEN '1er. Bimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (3, 4) THEN '2do. bimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (5, 6) THEN '3er. bimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (7, 8) THEN '4to. bimestre'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (9, 10) THEN '5to. bimestre'
                ELSE '6to. bimestre'
            END,
            EXTRACT(DAY FROM v_current_date),
            EXTRACT(MONTH FROM v_current_date),
            CASE EXTRACT(MONTH FROM v_current_date)  
				WHEN 1 THEN 'Enero'
				WHEN 2 THEN 'Febrero'
				WHEN 3 THEN 'Marzo'
				WHEN 4 THEN 'Abril'
				WHEN 5 THEN 'Mayo'
				WHEN 6 THEN 'Junio'
				WHEN 7 THEN 'Julio'
				WHEN 8 THEN 'Agosto'
				WHEN 9 THEN 'Septiembre'
				WHEN 10 THEN 'Octubre'
				WHEN 11 THEN 'Noviembre'
				WHEN 12 THEN 'Diciembre'
            END, 
            CASE EXTRACT(DOW FROM v_current_date)
				WHEN 0 THEN 7
				ELSE EXTRACT(DOW FROM v_current_date)
			END,
            CASE EXTRACT(DOW FROM v_current_date)
				WHEN 0 THEN 'Domingo'
				WHEN 1 THEN 'Lunes'
				WHEN 2 THEN 'Martes'
				WHEN 3 THEN 'Miércoles'
				WHEN 4 THEN 'Jueves'
				WHEN 5 THEN 'Viernes'
				WHEN 6 THEN 'Sábado'
			END,
            CASE
                WHEN EXTRACT(MONTH FROM v_current_date) IN (12, 1, 2) THEN 'Verano'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (3, 4, 5) THEN 'Otoño'
                WHEN EXTRACT(MONTH FROM v_current_date) IN (6, 7, 8) THEN 'Invierno'
                ELSE 'Primavera'
            END,
            /* CASE
                WHEN EXTRACT(DOW FROM v_current_date) IN (0, 6) THEN 'Fin de Semana'
                ELSE 'Día de Semana'
            END, */
			'Dia Laborable',
            EXTRACT(WEEK FROM v_current_date) - CASE 
				WHEN EXTRACT(WEEK FROM v_current_date) - EXTRACT(WEEK FROM DATE_TRUNC('month', v_current_date)) < 0 THEN 0
				ELSE EXTRACT(WEEK FROM DATE_TRUNC('month', v_current_date))
			END + 1,
			'Semana ' || 
			(EXTRACT(WEEK FROM v_current_date) - CASE 
				WHEN EXTRACT(WEEK FROM v_current_date) - EXTRACT(WEEK FROM DATE_TRUNC('month', v_current_date)) < 0 THEN 0
				ELSE EXTRACT(WEEK FROM DATE_TRUNC('month', v_current_date))
			END + 1)
			|| ' del mes',
            EXTRACT(WEEK FROM v_current_date),
			'Semana ' || EXTRACT(WEEK FROM v_current_date) || ' del año'
        );
        -- Incrementar la fecha en un día
        v_current_date := v_current_date + 1;
    END LOOP;
END;
$$;