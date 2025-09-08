CALL load_nomenclator_dim('postgres', '1234', 'OLTP');
CALL load_health_entity_dim('postgres', '1234', 'OLTP');
CALL load_professional_dim('postgres', '1234', 'OLTP');
CALL load_patient_dim('postgres', '1234', 'OLTP');

CALL load_piece_face_sector_dim();
CALL load_age_dimension();
CALL load_time_dimension();