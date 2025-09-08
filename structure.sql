CREATE EXTENSION dblink;

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
	
	-- Cargamos staging usando dblink con parámetros dinámicos
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
	GET DIAGNOSTICS new_version_records = ROW_COUNT;  -- Cantidad de registros actualizados (nuevas versiones)
	
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
    GET DIAGNOSTICS new_records = ROW_COUNT;  -- Cantidad de registros nuevos

    -- Mostrar resultados al operador
    RAISE NOTICE 'Cantidad de registros con nueva versión: %', new_version_records;
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
	
	-- Cargamos staging usando dblink con parámetros dinámicos
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
        RAISE NOTICE 'La tabla ya contiene datos. SP abortado.';
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