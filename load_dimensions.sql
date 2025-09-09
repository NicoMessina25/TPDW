CALL load_nomenclator_dim('postgres', '1234', 'OLTP');
CALL load_health_entity_dim('postgres', '1234', 'OLTP');
CALL load_professional_dim('postgres', '1234', 'OLTP');
CALL load_patient_dim('postgres', '1234', 'OLTP');
call load_office_dim('postgres','1234','OLTP');
call load_source_dim('postgres','1234','OLTP');

CALL load_piece_face_sector_dim();
CALL load_age_dim();
CALL load_time_dim();