-- ====================================================================
-- SCRIPT DE INICIALIZACIÓN Y ACTUALIZACIÓN DE BASE DE DATOS EN SUPABASE
-- Sistema de Presupuestos — SG MONTAJES SRL & ACOSTA SERVICIOS SRL
-- ====================================================================

-- 1. TABLA DE ESTADO GLOBAL SINCRONIZADO (REALTIME APP STATE)
-- Esta tabla permite sincronización instantánea y reactiva entre todas las terminales y sesiones.
CREATE TABLE IF NOT EXISTS public.app_state (
    id TEXT PRIMARY KEY DEFAULT 'globalData',
    pedidos JSONB DEFAULT '[]'::jsonb,
    users JSONB DEFAULT '[]'::jsonb,
    notifications JSONB DEFAULT '[]'::jsonb,
    user_permissions JSONB DEFAULT '{}'::jsonb,
    custom_prices JSONB DEFAULT '{}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.app_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura publica app_state" ON public.app_state;
CREATE POLICY "Permitir lectura publica app_state" ON public.app_state
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Permitir escritura publica app_state" ON public.app_state;
CREATE POLICY "Permitir escritura publica app_state" ON public.app_state
    FOR ALL USING (true) WITH CHECK (true);

-- 2. TABLAS RELACIONALES (Para consultas directas, reportes, BI y sincronización)

-- TABLA: USUARIOS
CREATE TABLE IF NOT EXISTS public.usuarios (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL DEFAULT '123',
    email TEXT,
    role TEXT NOT NULL DEFAULT 'Solicitante', -- Administrador, Autorizador, Solicitante, Congelado
    rubro_defecto TEXT NOT NULL DEFAULT 'Eléctrico', -- Eléctrico, Mecánico
    vendedor_codigo TEXT DEFAULT '',
    vendedor_nombre TEXT DEFAULT '',
    empresa TEXT NOT NULL DEFAULT 'SG MONTAJES SRL', -- 'SG MONTAJES SRL', 'ACOSTA SERVICIOS SRL'
    permisos JSONB DEFAULT '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb,
    can_edit_prices BOOLEAN DEFAULT false
);

-- Migraciones idempotentes para tabla usuarios
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS vendedor_codigo TEXT DEFAULT '';
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS vendedor_nombre TEXT DEFAULT '';
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS empresa TEXT DEFAULT 'SG MONTAJES SRL';
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS permisos JSONB DEFAULT '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS can_edit_prices BOOLEAN DEFAULT false;

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
    importe_neto NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    estado TEXT NOT NULL DEFAULT 'Enviado sin OC',
    nro_oc TEXT,
    nro_ot TEXT,
    motivo_rechazo TEXT,
    operador TEXT NOT NULL DEFAULT 'admin',
    condicion_id TEXT,
    condicion_nombre TEXT,
    condicion_venta TEXT DEFAULT 'CONTADO',
    motivo TEXT,
    
    -- Campos de Oferta e Instalación (Eléctrico y Mecánico)
    denominacion TEXT,
    proveedor TEXT NOT NULL DEFAULT 'SG MONTAJES SRL',
    fecha_oferta TEXT,
    validez TEXT,
    planta TEXT,
    fecha_inicio TEXT,
    duracion TEXT,
    fecha_fin TEXT,
    propuesta TEXT,
    personal TEXT,
    exclusiones TEXT,
    observaciones TEXT DEFAULT '',
    domicilio TEXT DEFAULT '',
    localidad TEXT DEFAULT '',
    vendedor_nombre TEXT DEFAULT '',
    
    -- Avance y Facturación
    avance_porcentaje_acumulado NUMERIC(5, 2) DEFAULT 0.00,
    facturado_porcentaje NUMERIC(5, 2) DEFAULT 0.00,
    monto_facturado NUMERIC(15, 2) DEFAULT 0.00,
    tipo_reporte TEXT DEFAULT 'detallado',
    items JSONB DEFAULT '[]'::jsonb,
    avances JSONB DEFAULT '[]'::jsonb
);

-- Migraciones idempotentes para tabla presupuestos
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS nro_ot TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS importe_neto NUMERIC(15, 2) DEFAULT 0.00;
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS proveedor TEXT DEFAULT 'SG MONTAJES SRL';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS observaciones TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS tipo_reporte TEXT DEFAULT 'detallado';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS condicion_venta TEXT DEFAULT 'CONTADO';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS domicilio TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS localidad TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS cuit TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS vendedor_nombre TEXT DEFAULT '';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS avances JSONB DEFAULT '[]'::jsonb;

ALTER TABLE public.presupuestos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso presupuestos" ON public.presupuestos;
CREATE POLICY "Permitir acceso presupuestos" ON public.presupuestos FOR ALL USING (true) WITH CHECK (true);

-- TABLA: TARIFARIO (Catálogo de Precios de Ítems en Tiempo Real)
CREATE TABLE IF NOT EXISTS public.tarifario (
    id TEXT PRIMARY KEY,
    codigo TEXT NOT NULL,
    detalle TEXT NOT NULL,
    rubro TEXT,
    subrubro TEXT,
    unidad TEXT DEFAULT 'Hs',
    precio NUMERIC(15, 2) DEFAULT 0.00,
    stock NUMERIC(10, 2) DEFAULT 999,
    estado TEXT DEFAULT 'ACTIVOS',
    is_custom BOOLEAN DEFAULT false,
    planta TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.tarifario ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso tarifario" ON public.tarifario;
CREATE POLICY "Permitir acceso tarifario" ON public.tarifario FOR ALL USING (true) WITH CHECK (true);

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
    user_id TEXT,
    tipo TEXT DEFAULT 'general',
    titulo TEXT DEFAULT '',
    mensaje TEXT NOT NULL,
    leida BOOLEAN DEFAULT false,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    task_id TEXT
);

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir notificaciones" ON public.notificaciones;
CREATE POLICY "Permitir notificaciones" ON public.notificaciones FOR ALL USING (true) WITH CHECK (true);

-- TABLA: CLIENTES
CREATE TABLE IF NOT EXISTS public.clientes (
    id TEXT PRIMARY KEY,
    codigo TEXT UNIQUE NOT NULL,
    nombre TEXT NOT NULL,
    cuit TEXT,
    telefono TEXT,
    email TEXT,
    condicion_id TEXT DEFAULT '1',
    condicion_nombre TEXT DEFAULT 'CONTADO',
    deposito_id TEXT DEFAULT '0',
    deposito_nombre TEXT DEFAULT 'Depósito 0',
    transporte_id TEXT DEFAULT '0',
    transporte_nombre TEXT DEFAULT 'Transporte 0',
    vendedor_id TEXT DEFAULT '1',
    vendedor_nombre TEXT DEFAULT '',
    estado TEXT DEFAULT 'ACTIVOS',
    domicilio TEXT DEFAULT '',
    localidad TEXT DEFAULT '',
    deuda_actual NUMERIC(15, 2) DEFAULT 0.00,
    facturas_mora JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso clientes" ON public.clientes;
CREATE POLICY "Permitir acceso clientes" ON public.clientes FOR ALL USING (true) WITH CHECK (true);

-- TABLA: PLANTAS (Gestión de Plantas y Reglas de Listas de Precios)
CREATE TABLE IF NOT EXISTS public.plantas (
    nombre TEXT PRIMARY KEY,
    usa_lista_de TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.plantas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso plantas" ON public.plantas;
CREATE POLICY "Permitir acceso plantas" ON public.plantas FOR ALL USING (true) WITH CHECK (true);

-- TABLA: COLA DE EMAILS (Para envío asíncrono y workers cloud)
CREATE TABLE IF NOT EXISTS public.cola_emails (
    id TEXT PRIMARY KEY,
    destinatarios JSONB DEFAULT '[]'::jsonb,
    cc JSONB DEFAULT '[]'::jsonb,
    bcc JSONB DEFAULT '[]'::jsonb,
    asunto TEXT NOT NULL DEFAULT '',
    cuerpo_html TEXT DEFAULT '',
    cuerpo_texto TEXT DEFAULT '',
    adjuntos JSONB DEFAULT '[]'::jsonb,
    estado TEXT DEFAULT 'pendiente',
    error_mensaje TEXT,
    procesado_en TIMESTAMP WITH TIME ZONE,
    creado_en TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);
-- Migración idempotente: agregar procesado_en si no existe
ALTER TABLE public.cola_emails ADD COLUMN IF NOT EXISTS procesado_en TIMESTAMP WITH TIME ZONE;

ALTER TABLE public.cola_emails ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso cola_emails" ON public.cola_emails;
CREATE POLICY "Permitir acceso cola_emails" ON public.cola_emails FOR ALL USING (true) WITH CHECK (true);

-- ====================================================================
-- HABILITACIÓN DE SUPABASE REALTIME PARA TODAS LAS TABLAS ACTIVAS
-- ====================================================================
DO $$
DECLARE
    t TEXT;
    tablas TEXT[] := ARRAY['app_state', 'usuarios', 'presupuestos', 'tarifario', 'clientes', 'notificaciones', 'avances_obra', 'plantas'];
BEGIN
    FOREACH t IN ARRAY tablas LOOP
        IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = t) THEN
            IF NOT EXISTS (
                SELECT 1 FROM pg_publication_tables 
                WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
            ) THEN
                EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', t);
            END IF;
        END IF;
    END LOOP;
END $$;

-- ====================================================================
-- SEED DATA: CARGA INICIAL DIRECTA EN SUPABASE
-- ====================================================================

-- Cargar los 11 Clientes Oficiales
INSERT INTO public.clientes (id, codigo, nombre, cuit, telefono, email, condicion_id, condicion_nombre, deposito_id, deposito_nombre, transporte_id, transporte_nombre, vendedor_id, vendedor_nombre, estado, domicilio, localidad, deuda_actual)
VALUES
    ('ACOSTA SERVICIOS SRL - 30718686217', '7', 'ACOSTA SERVICIOS SRL', '30718686217', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'Estanislao López', 'TIMBUES', 0.00),
    ('CARGILL SACI - 30506792165_2', '2', 'CARGILL SACI', '30506792165', '3415890126', '8', '2', '30 Y 60 DIAS 50\50', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'YRIGOYEN Y PUNTA QUBRACHO', 'PUERTO GENERAL SAN MARTIN', 0.00),
    ('CARGILL SACI - 30506792165_3', '3', 'CARGILL SACI', '30506792165', '3413269645', '9', '2', '30 Y 60 DIAS 50\50', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'SOLIS 822', 'VILLA GOBERNADOR GALVEZ', 0.00),
    ('CARGILL SACI - 30506792165_4', '4', 'CARGILL SACI', '30506792165', '', '', '3', '30 DIAS', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'LUIS RAUL MAZA 35', 'BERNARDO LARROUDE', 0.00),
    ('CONSUMIDOR FINAL - 23402204', '1', 'CONSUMIDOR FINAL', '23402204', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', '', 'ROSARIO', 0.00),
    ('JULIO ALVAREZ - 30716236990', '5', 'JULIO ALVAREZ', '30716236990', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'BS AS 1122', 'PUERTO GENERAL SAN MARTIN', 0.00),
    ('PV SERVICIOS SRL - 30716598205', '10', 'PV SERVICIOS SRL', '30716598205', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', '', '', 0.00),
    ('SAO CLIMA SRL - 30715472313', '11', 'SAO CLIMA SRL', '30715472313', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'GRAL PAZ 344', 'CAPITAN BERMUDEZ', 0.00),
    ('SILC SERVICIOS SRL - 30717824594', '8', 'SILC SERVICIOS SRL', '30717824594', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', '', '', 0.00),
    ('T6 INDUSTRIAL S.A - 33689206099', '9', 'T6 INDUSTRIAL S.A', '33689206099', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'Hipolito Yrigoyen y Gral. Luci', 'PUERTO GENERAL SAN MARTIN', 0.00),
    ('Terminal 6 s.a - 30615829699', '6', 'Terminal 6 s.a', '30615829699', '', '', '1', 'CONTADO', '0', 'Depósito 0', '0', 'Transporte 0', '1', '', 'ACTIVOS', 'Hipolito Yrigoyen y Costa Del', 'PUERTO GENERAL SAN MARTIN', 0.00)
ON CONFLICT (codigo) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    cuit = EXCLUDED.cuit,
    condicion_id = EXCLUDED.condicion_id,
    condicion_nombre = EXCLUDED.condicion_nombre,
    domicilio = EXCLUDED.domicilio,
    localidad = EXCLUDED.localidad;

-- Cargar los 9 usuarios oficiales con empresa asignada, permisos y control de edición de precios
INSERT INTO public.usuarios (id, username, password, email, role, rubro_defecto, vendedor_codigo, vendedor_nombre, empresa, can_edit_prices, permisos)
VALUES
    ('1', 'mel', '123', 'mel@empresa.com', 'Administrador', 'Eléctrico', '', '', 'SG MONTAJES SRL', true, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-admin", "menu-facturacion", "menu-all-ver", "menu-all-edit", "menu-ingresar-edit-price", "edit-precios"]'::jsonb),
    ('2', 'juanluis', '123', 'grandijuanluis@gmail.com', 'Solicitante', 'Eléctrico', '103', 'Juan Luis', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb),
    ('3', 'luciano', '123', 'luciano@sgmontajes.com', 'Solicitante', 'Eléctrico', '102', 'Luciano', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb),
    ('4', 'roberto', '123', 'Roberto@sgmontajes.com', 'Solicitante', 'Mecánico', '104', 'Roberto', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb),
    ('5', 'melani', '123', 'melanidaiana28@gmail.com', 'Administrador', 'Eléctrico', '', '', 'SG MONTAJES SRL', true, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-admin", "menu-facturacion", "menu-all-ver", "menu-all-edit", "menu-ingresar-edit-price", "edit-precios"]'::jsonb),
    ('6', 'nicole', '123', 'nicole@sgmontajes.com', 'Solicitante', 'Eléctrico', '105', 'Nicole', 'SG MONTAJES SRL', false, '["menu-facturacion"]'::jsonb),
    ('7', 'alexis', '123', 'alexis@sgmontajes.com', 'Solicitante', 'Mecánico', '106', 'Alexis', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb),
    ('8', 'emiliano', '123', 'emiliano@sgmontajes.com', 'Solicitante', 'Eléctrico', '107', 'Emiliano', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb),
    ('9', 'hernan', '123', 'hernan@sgmontajes.com', 'Solicitante', 'Eléctrico', '108', 'Hernán', 'SG MONTAJES SRL', false, '["menu-ingresar", "menu-all", "menu-estado-presupuesto", "menu-rechazados", "menu-facturacion", "menu-all-ver", "menu-all-edit"]'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    role = EXCLUDED.role,
    rubro_defecto = EXCLUDED.rubro_defecto,
    vendedor_codigo = EXCLUDED.vendedor_codigo,
    vendedor_nombre = EXCLUDED.vendedor_nombre,
    empresa = EXCLUDED.empresa,
    can_edit_prices = EXCLUDED.can_edit_prices,
    permisos = EXCLUDED.permisos;
