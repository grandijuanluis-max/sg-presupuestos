-- ====================================================================
-- SCRIPT DE INICIALIZACIÓN DE BASE DE DATOS EN SUPABASE
-- Sistema de Presupuestos — SG MONTAJES SRL
-- ====================================================================

-- 1. TABLA DE ESTADO GLOBAL SINCRONIZADO (REALTIME APP STATE)
-- Esta tabla permite sincronización instantánea y reactiva entre todas las terminales y sesiones.
CREATE TABLE IF NOT EXISTS public.app_state (
    id TEXT PRIMARY KEY DEFAULT 'globalData',
    pedidos JSONB DEFAULT '[]'::jsonb,
    users JSONB DEFAULT '[]'::jsonb,
    notifications JSONB DEFAULT '[]'::jsonb,
    user_permissions JSONB DEFAULT '{}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.app_state ENABLE ROW LEVEL SECURITY;

-- Políticas de acceso para app_state (permite lectura y escritura pública/anónima para la aplicación web)
DROP POLICY IF EXISTS "Permitir lectura publica app_state" ON public.app_state;
CREATE POLICY "Permitir lectura publica app_state" ON public.app_state
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Permitir escritura publica app_state" ON public.app_state;
CREATE POLICY "Permitir escritura publica app_state" ON public.app_state
    FOR ALL USING (true) WITH CHECK (true);

-- Habilitar Supabase Realtime para la tabla app_state
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'app_state'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_state;
    END IF;
END $$;

-- 2. TABLAS RELACIONALES (Para consultas SQL directas, reportes y BI)

-- TABLA: USUARIOS
DROP TABLE IF EXISTS public.usuarios CASCADE;
CREATE TABLE public.usuarios (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL DEFAULT '123',
    email TEXT,
    role TEXT NOT NULL DEFAULT 'Solicitante', -- Administrador, Autorizador, Solicitante, Congelado
    rubro_defecto TEXT NOT NULL DEFAULT 'Eléctrico' -- Eléctrico, Mecánico
);

ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso usuarios" ON public.usuarios;
CREATE POLICY "Permitir acceso usuarios" ON public.usuarios FOR ALL USING (true) WITH CHECK (true);

-- TABLA: PRESUPUESTOS
CREATE TABLE IF NOT EXISTS public.presupuestos (
    id TEXT PRIMARY KEY, -- Ej: '101-MEC-0001', '102-ELEC-0001'
    fecha TEXT,
    tipo_presupuesto TEXT NOT NULL, -- 'Eléctrico' | 'Mecánico'
    cliente_id TEXT NOT NULL,
    cliente_nombre TEXT NOT NULL,
    cuit TEXT,
    telefono TEXT,
    email TEXT,
    importe NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    estado TEXT NOT NULL DEFAULT 'Enviado sin OC',
    nro_oc TEXT,
    motivo_rechazo TEXT,
    operador TEXT,
    condicion_id TEXT,
    condicion_nombre TEXT,
    motivo TEXT,
    
    -- Campos de Oferta e Instalación (Eléctrico y Mecánico)
    denominacion TEXT,
    proveedor TEXT,
    fecha_oferta TEXT,
    validez TEXT,
    planta TEXT,
    nro_ot TEXT,
    fecha_inicio TEXT,
    duracion TEXT,
    fecha_fin TEXT,
    propuesta TEXT,
    personal TEXT,
    exclusiones TEXT,
    
    -- Avance y Facturación
    avance_porcentaje_acumulado NUMERIC(5, 2) DEFAULT 0.00,
    facturado_porcentaje NUMERIC(5, 2) DEFAULT 0.00,
    monto_facturado NUMERIC(15, 2) DEFAULT 0.00,
    tipo_reporte TEXT DEFAULT 'detallado',
    items JSONB DEFAULT '[]'::jsonb
);

ALTER TABLE public.presupuestos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso presupuestos" ON public.presupuestos;
CREATE POLICY "Permitir acceso presupuestos" ON public.presupuestos FOR ALL USING (true) WITH CHECK (true);

-- TABLA: AVANCES DE OBRA
CREATE TABLE IF NOT EXISTS public.avances_obra (
    id TEXT PRIMARY KEY, -- Ej: '102-ELEC-0001-AV-01'
    presupuesto_id TEXT REFERENCES public.presupuestos(id) ON DELETE CASCADE,
    fecha DATE NOT NULL,
    porcentaje NUMERIC(5, 2) NOT NULL,
    monto_equivalente NUMERIC(15, 2) NOT NULL,
    nro_documento TEXT,
    detalle TEXT
);

ALTER TABLE public.avances_obra ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso avances_obra" ON public.avances_obra;
CREATE POLICY "Permitir acceso avances_obra" ON public.avances_obra FOR ALL USING (true) WITH CHECK (true);

-- TABLA: ITEMS DE PRESUPUESTO
CREATE TABLE IF NOT EXISTS public.presupuesto_items (
    id TEXT PRIMARY KEY, -- Ej: '102-ELEC-0001-ITM-01'
    presupuesto_id TEXT REFERENCES public.presupuestos(id) ON DELETE CASCADE,
    codigo TEXT,
    detalle TEXT NOT NULL,
    rubro TEXT,
    subrubro TEXT,
    cantidad NUMERIC(10, 2) NOT NULL DEFAULT 1,
    unidad TEXT DEFAULT 'UN',
    precio_unitario NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    subtotal NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    orden INT DEFAULT 0
);

ALTER TABLE public.presupuesto_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir presupuesto_items" ON public.presupuesto_items;
CREATE POLICY "Permitir presupuesto_items" ON public.presupuesto_items FOR ALL USING (true) WITH CHECK (true);

-- TABLA: NOTIFICACIONES
CREATE TABLE IF NOT EXISTS public.notificaciones (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    message TEXT NOT NULL,
    read BOOLEAN DEFAULT false,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    task_id TEXT
);

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir notificaciones" ON public.notificaciones;
CREATE POLICY "Permitir notificaciones" ON public.notificaciones FOR ALL USING (true) WITH CHECK (true);

-- ====================================================================
-- SEED DATA: CARGA INICIAL DIRECTA EN SUPABASE
-- ====================================================================

-- Cargar los 8 usuarios oficiales
INSERT INTO public.usuarios (id, username, password, email, role, rubro_defecto, vendedor_codigo, vendedor_nombre)
VALUES
    ('1', 'mel', '123', 'mel@empresa.com', 'Administrador', 'Eléctrico', '', ''),
    ('2', 'juanluis', '123', 'grandijuanluis@gmail.com', 'Solicitante', 'Eléctrico', '', ''),
    ('3', 'luciano', '123', 'luciano@sgmontajes.com', 'Solicitante', 'Eléctrico', '', ''),
    ('4', 'roberto', '123', 'Roberto@sgmontajes.com', 'Solicitante', 'Mecánico', '', ''),
    ('5', 'melani', '123', 'melanidaiana28@gmail.com', 'Administrador', 'Eléctrico', '', ''),
    ('6', 'nicole', '123', 'nicole@sgmontajes.com', 'Solicitante', 'Eléctrico', '', ''),
    ('7', 'alexis', '123', 'alexis@sgmontajes.com', 'Solicitante', 'Mecánico', '', ''),
    ('8', 'emiliano', '123', 'emiliano@sgmontajes.com', 'Solicitante', 'Eléctrico', '', '')
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    role = EXCLUDED.role,
    rubro_defecto = EXCLUDED.rubro_defecto;

-- Cargar Presupuestos Iniciales
INSERT INTO public.presupuestos (id, fecha, tipo_presupuesto, cliente_id, cliente_nombre, cuit, importe, estado, nro_oc, tipo_reporte, meca_denominacion, meca_planta)
VALUES
    ('102-ELEC-0001', NOW(), 'Eléctrico', '3', 'CARGILL SACI', '30-50679316-5', 450000.00, 'Enviado sin OC', 'OC-9921', 'detallado', 'MONTAJE TABLERO Y CANALIZACIÓN ELÉCTRICA', 'PGSM'),
    ('101-MEC-0001', NOW(), 'Mecánico', '3', 'CARGILL SACI', '30-50679316-5', 1250000.00, 'Enviado sin OC', 'OC-8832', 'resumido', 'MANTENIMIENTO MECÁNICO LÍNEA DE MOLINOS', 'VGG')
ON CONFLICT (id) DO NOTHING;

-- Cargar Estado Global Inicial
INSERT INTO public.app_state (id, pedidos, users, notifications, user_permissions, updated_at)
VALUES (
    'globalData',
    '[
        {"id":"102-ELEC-0001","fecha":"2026-03-01 10:00:00","cliente_id":"3","cliente_nombre":"CARGILL SACI","cuit":"30-50679316-5","importe":450000,"estado":"Enviado sin OC","tipo_presupuesto":"Eléctrico","tipo_reporte":"detallado","meca_denominacion":"MONTAJE TABLERO Y CANALIZACIÓN ELÉCTRICA","meca_planta":"PGSM","items":[{"codigo":"ELE-0001","detalle":"Tendido de Cableado","cantidad":10,"precio":45000,"subtotal":450000,"estado":"Pendiente"}]},
        {"id":"101-MEC-0001","fecha":"2026-03-02 11:30:00","cliente_id":"3","cliente_nombre":"CARGILL SACI","cuit":"30-50679316-5","importe":1250000,"estado":"Enviado sin OC","tipo_presupuesto":"Mecánico","tipo_reporte":"resumido","meca_denominacion":"MANTENIMIENTO MECÁNICO LÍNEA DE MOLINOS","meca_planta":"VGG","items":[{"codigo":"MEC-0001","detalle":"Mano de Obra en Taller","cantidad":25,"precio":50000,"subtotal":1250000,"estado":"Pendiente"}]}
    ]'::jsonb,
    '[
        {"id":"1","username":"mel","password":"123","email":"mel@empresa.com","role":"Administrador","rubro_defecto":"Eléctrico"},
        {"id":"2","username":"juanluis","password":"123","email":"grandijuanluis@gmail.com","role":"Solicitante","rubro_defecto":"Eléctrico"},
        {"id":"3","username":"luciano","password":"123","email":"luciano@sgmontajes.com","role":"Solicitante","rubro_defecto":"Eléctrico"},
        {"id":"4","username":"roberto","password":"123","email":"Roberto@sgmontajes.com","role":"Solicitante","rubro_defecto":"Mecánico"},
        {"id":"5","username":"melani","password":"123","email":"melanidaiana28@gmail.com","role":"Administrador","rubro_defecto":"Eléctrico"},
        {"id":"6","username":"nicole","password":"123","email":"nicole@sgmontajes.com","role":"Solicitante","rubro_defecto":"Eléctrico"},
        {"id":"7","username":"alexis","password":"123","email":"alexis@sgmontajes.com","role":"Solicitante","rubro_defecto":"Mecánico"},
        {"id":"8","username":"emiliano","password":"123","email":"emiliano@sgmontajes.com","role":"Solicitante","rubro_defecto":"Eléctrico"}
    ]'::jsonb,
    '[]'::jsonb,
    '{}'::jsonb,
    NOW()
)
ON CONFLICT (id) DO UPDATE SET
    updated_at = EXCLUDED.updated_at;
