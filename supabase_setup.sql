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
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS moneda TEXT DEFAULT 'ARS';
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS moneda_id INT DEFAULT 1;
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS cotizacion NUMERIC(15, 2) DEFAULT 1450.00;
ALTER TABLE public.presupuestos ADD COLUMN IF NOT EXISTS cotizacion_materiales NUMERIC(15, 2) DEFAULT 1450.00;

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
    moneda TEXT DEFAULT 'ARS',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.tarifario ADD COLUMN IF NOT EXISTS moneda TEXT DEFAULT 'ARS';
ALTER TABLE public.tarifario ADD COLUMN IF NOT EXISTS precio_ars NUMERIC(15, 2);
ALTER TABLE public.tarifario ADD COLUMN IF NOT EXISTS precio_usd NUMERIC(15, 2);
ALTER TABLE public.tarifario ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir acceso tarifario" ON public.tarifario;
CREATE POLICY "Permitir acceso tarifario" ON public.tarifario FOR ALL USING (true) WITH CHECK (true);

-- SEEDING: ÍTEMS OFICIALES BASE DEL TARIFARIO (ELÉCTRICO Y MECÁNICO)
INSERT INTO public.tarifario (id, codigo, detalle, rubro, subrubro, unidad, precio, stock, estado, is_custom, planta, moneda)
VALUES
    ('ELE-001', 'ELE-001', 'CAJA ALUMINIO 200X200X100', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-002', 'ELE-002', 'CAJA ALUMINIO 300X300X100', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-003', 'ELE-003', 'CONDULET ( L ) 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-004', 'ELE-004', 'CONDULET DE PASO 1"1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-005', 'ELE-005', 'UNION DOBLE 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-006', 'ELE-006', 'CUPLAS 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-007', 'ELE-007', 'GRAMPAS U-BOLT 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-008', 'ELE-008', 'FLEXIBLE ZOLODA 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-009', 'ELE-009', 'CONECTOR ZOLODA CON TUERCA 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-010', 'ELE-010', 'CAÑO ACERO GALVANIZADO SEMIPESADO 1" 1/2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-011', 'ELE-011', 'CINTA PROTECCION SE CAÑOS POLIGUARD', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-012', 'ELE-012', 'BARRA UPN 80 MM X 6 MTS', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-013', 'ELE-013', 'BARRA ANGULO 1" 1/2 X 3,16 X 6 MTS', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-014', 'ELE-014', 'LLAVE SELECTORA 0.1.2', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-015', 'ELE-015', 'CABLE 485', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-016', 'ELE-016', 'CABLE SINTENAX 7X1,5 MM', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-017', 'ELE-017', 'CABLE SINTENAX 3X1,5 MM', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-018', 'ELE-018', 'CABLE SINTENAX 3X2,5 MM', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-019', 'ELE-019', 'BROCA 10 MM', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-020', 'ELE-020', 'BULON 1/4X1"1/2CON DOBLE ARANDELA PLANA + TUERCA', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-021', 'ELE-021', 'BULON 5/16X 1"1/2 CON DOBLE ARANDELA PLANA Y TUERCA', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-022', 'ELE-022', 'PINTURA AMARILLA', 'Eléctrico', 'Materiales y Equipos', 'LTS', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-023', 'ELE-023', 'PINTURA NEGRO', 'Eléctrico', 'Materiales y Equipos', 'LTS', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-024', 'ELE-024', 'CINTA REFLECTIVA ROJO/NEGRO ADHESIVA', 'Eléctrico', 'Materiales y Equipos', 'mts', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-025', 'ELE-025', 'TUERCA 1" 1/2 PARA CAÑOS', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-026', 'ELE-026', 'BOQUILLA 1" 1/2 ALUMINIO', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-027', 'ELE-027', 'RIEL DIN', 'Eléctrico', 'Materiales y Equipos', 'c/u', 0.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-038', 'ELE-038', 'Técnico en Seguridad', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 5695.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-039', 'ELE-039', 'Oficial Esp', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 11712.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-040', 'ELE-040', 'Ayudante', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 9992.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-041', 'ELE-041', 'Supervisor', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 12072.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-042', 'ELE-042', 'Camion Hidro elevador', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-033', 'ELE-033', 'Tecnico en seguridad', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 5695.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-034', 'ELE-034', 'Oficial Esp', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 11712.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-035', 'ELE-035', 'Ayudante', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 9992.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-036', 'ELE-036', 'Supervisor', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 12072.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-037', 'ELE-037', 'Hidro elevador', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'u', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-028', 'ELE-028', 'Tecnico en seguridad', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 10023.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-029', 'ELE-029', 'Oficial Esp', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 20616.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-030', 'ELE-030', 'Ayudante', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 17577.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-031', 'ELE-031', 'Supervisor', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'horas', 16363.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-032', 'ELE-032', 'Hidro elevador', 'Eléctrico', 'Mano de Obra MANTENIMIENTO', 'u', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-043', 'ELE-043', 'Técnico en Seguridad', 'Eléctrico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 28468.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-044', 'ELE-044', 'Oficial Esp', 'Eléctrico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 59347.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-045', 'ELE-045', 'Camion Hidro elevador', 'Eléctrico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'u', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-056', 'ELE-056', 'Técnico en Seguridad', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 4386.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-057', 'ELE-057', 'Oficial Esp', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 11871.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-058', 'ELE-058', 'Ayudante', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 10128.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-059', 'ELE-059', 'Supervisor', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 12233.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-060', 'ELE-060', 'Camion Hidro elevador', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-051', 'ELE-051', 'Tecnico en seguridad', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 5964.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-052', 'ELE-052', 'Oficial Esp', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 16141.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-053', 'ELE-053', 'Ayudante', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 10128.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-054', 'ELE-054', 'Supervisor', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 16141.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-055', 'ELE-055', 'Hidro elevador', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'u', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-046', 'ELE-046', 'Tecnico en seguridad', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 7720.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-047', 'ELE-047', 'Oficial Esp', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 20889.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-048', 'ELE-048', 'Ayudante', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 17830.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-049', 'ELE-049', 'Supervisor', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'horas', 21521.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('ELE-050', 'ELE-050', 'Hidro elevador', 'Eléctrico', 'Mano de Obra PARADA DE PLANTA', 'u', 24028.0, 999.0, 'ACTIVOS', false, '', 'ARS'),
    ('MEC-001_APS_ARS', 'MEC-001', 'Hidroelevador', 'Mecánico', 'Materiales y Equipos', 'u', 83983.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-002_APS_ARS', 'MEC-002', 'Hidro elevador con barquilla', 'Mecánico', 'Materiales y Equipos', 'u', 71062.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-003_APS_ARS', 'MEC-003', 'Alquiler de oficinas', 'Mecánico', 'Materiales y Equipos', 'u', 310089.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-004_APS_ARS', 'MEC-004', 'Alquiler de manitou (incluye chofer y combustible)', 'Mecánico', 'Materiales y Equipos', 'u', 137566.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-005_APS_ARS', 'MEC-005', 'Traslados ida y vuelta para APG/PA', 'Mecánico', 'Materiales y Equipos', 'u', 464144.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-006_APS_ARS', 'MEC-006', 'Traslados ida y vuelta para APS', 'Mecánico', 'Materiales y Equipos', 'u', 111842.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-007_APS_ARS', 'MEC-007', 'Relevamiento', 'Mecánico', 'Materiales y Equipos', 'u', 1750000.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-008_APS_ARS', 'MEC-008', 'Documentos y 3D', 'Mecánico', 'Materiales y Equipos', 'u', 5120350.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-009_APS_ARS', 'MEC-009', 'Ing. Civil', 'Mecánico', 'Materiales y Equipos', 'u', 4350000.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-010_APS_ARS', 'MEC-010', 'Ayudante (Taller)', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 25275.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-011_APS_ARS', 'MEC-011', 'Medio Oficial (Taller)', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 25319.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-012_APS_ARS', 'MEC-012', 'Oficial (Taller)', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 26444.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-013_APS_ARS', 'MEC-013', 'Oficial Especializado (Taller)', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 28652.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-014_APS_ARS', 'MEC-014', 'Oficial soldador calificado combinado procesos SMAW / GTAW', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 28652.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-015_APS_ARS', 'MEC-015', 'Supervisor (Taller)', 'Mecánico', 'Mano de Obra EN TALLER', 'horas', 29601.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-016_APS_ARS', 'MEC-016', 'Ayudante hora Normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 28657.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-017_APS_ARS', 'MEC-017', 'Medio Oficial hora normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 28962.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-018_APS_ARS', 'MEC-018', 'Oficial hora normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 30423.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-019_APS_ARS', 'MEC-019', 'Oficial Especializado hora normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 33654.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-020_APS_ARS', 'MEC-020', 'Oficial soldador calificado hora normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 33654.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-021_APS_ARS', 'MEC-021', 'Supervisor horas normales (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 34672.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-022_APS_ARS', 'MEC-022', 'Técnico HyS hora normal (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 27419.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-023_APS_ARS', 'MEC-023', 'Ayudante hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 38969.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-024_APS_ARS', 'MEC-024', 'Medio Oficial hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 39391.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-025_APS_ARS', 'MEC-025', 'Oficial hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 41366.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-026_APS_ARS', 'MEC-026', 'Oficial Especializado hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 45753.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-027_APS_ARS', 'MEC-027', 'Oficial soldador calificado hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 45753.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-028_APS_ARS', 'MEC-028', 'Supervisor horas EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 47146.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-029_APS_ARS', 'MEC-029', 'Técnico HyS hora EXTRA SIMPLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 37290.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-030_APS_ARS', 'MEC-030', 'Ayudante hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 50421.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-031_APS_ARS', 'MEC-031', 'Medio Oficial hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 50981.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-032_APS_ARS', 'MEC-032', 'Oficial hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 53523.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-033_APS_ARS', 'MEC-033', 'Oficial Especializado hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 59216.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-034_APS_ARS', 'MEC-034', 'Oficial soldador calificado hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 59216.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-035_APS_ARS', 'MEC-035', 'Supervisor hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 61016.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-036_APS_ARS', 'MEC-036', 'Técnico HyS hora EXTRA DOBLE (Mantenimiento)', 'Mecánico', 'Mano de Obra MANTENIMIENTO', 'horas', 48806.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-037_APS_ARS', 'MEC-037', 'Ayudante hora Normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 29067.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-038_APS_ARS', 'MEC-038', 'Medio Oficial hora normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 29422.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-039_APS_ARS', 'MEC-039', 'Oficial hora normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 30866.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-040_APS_ARS', 'MEC-040', 'Oficial Especializado hora normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 34186.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-041_APS_ARS', 'MEC-041', 'Oficial soldador calificado hora normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 34186.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-042_APS_ARS', 'MEC-042', 'Supervisor horas normales (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 35214.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-043_APS_ARS', 'MEC-043', 'Técnico HyS hora normal (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 27419.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-044_APS_ARS', 'MEC-044', 'Ayudante hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 39525.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-045_APS_ARS', 'MEC-045', 'Medio Oficial hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 40011.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-046_APS_ARS', 'MEC-046', 'Oficial hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 41995.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-047_APS_ARS', 'MEC-047', 'Oficial Especializado hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 46504.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-048_APS_ARS', 'MEC-048', 'Oficial soldador calificado hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 46504.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-049_APS_ARS', 'MEC-049', 'Supervisor horas EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 47883.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-050_APS_ARS', 'MEC-050', 'Técnico HyS hora EXTRA SIMPLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 37290.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-051_APS_ARS', 'MEC-051', 'Ayudante hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 51162.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-052_APS_ARS', 'MEC-052', 'Medio Oficial hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 51775.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-053_APS_ARS', 'MEC-053', 'Oficial hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 54349.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-054_APS_ARS', 'MEC-054', 'Oficial Especializado hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 60180.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-055_APS_ARS', 'MEC-055', 'Oficial soldador calificado hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 60180.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-056_APS_ARS', 'MEC-056', 'Supervisor hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 61969.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-057_APS_ARS', 'MEC-057', 'Técnico HyS hora EXTRA DOBLE (Parada de Planta)', 'Mecánico', 'Mano de Obra PARADA DE PLANTA', 'horas', 48806.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-058_APS_ARS', 'MEC-058', 'Ayudante hora EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 145335.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-059_APS_ARS', 'MEC-059', 'Medio Oficial hora EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 147114.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-060_APS_ARS', 'MEC-060', 'Oficial hora normal (Emergencia)', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 154390.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-061_APS_ARS', 'MEC-061', 'Oficial Especializado hora EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 170957.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-062_APS_ARS', 'MEC-062', 'Oficial soldador calificado hora EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 170957.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-063_APS_ARS', 'MEC-063', 'Supervisor horas EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 176052.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS'),
    ('MEC-064_APS_ARS', 'MEC-064', 'Técnico HyS hora EMERGENCIA', 'Mecánico', 'Mano de Obra EMERGENCIA MANTENIMIENTO', 'horas', 165659.0, 999.0, 'ACTIVOS', false, 'APS', 'ARS')
ON CONFLICT (id) DO UPDATE SET
    detalle = EXCLUDED.detalle,
    rubro = EXCLUDED.rubro,
    subrubro = EXCLUDED.subrubro,
    unidad = EXCLUDED.unidad,
    stock = EXCLUDED.stock,
    estado = EXCLUDED.estado,
    is_custom = false;


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
    orden INT DEFAULT 0,
    moneda TEXT DEFAULT 'ARS'
);

ALTER TABLE public.presupuesto_items ADD COLUMN IF NOT EXISTS moneda TEXT DEFAULT 'ARS';
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
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    codigo TEXT UNIQUE NOT NULL,
    nombre TEXT NOT NULL,
    cuit TEXT,
    telefono TEXT,
    email TEXT,
    domicilio TEXT DEFAULT '',
    localidad TEXT DEFAULT '',
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

-- Cargar los 14 Clientes Oficiales
INSERT INTO public.clientes (id, codigo, nombre, cuit, telefono, email, domicilio, localidad)
VALUES
    (1, '1', 'CONSUMIDOR FINAL', '23402204', '', '', '', 'ROSARIO'),
    (2, '2', 'CARGILL SACI', '30506792165', '3415890126', 'matias_marchisio@cargill.com', 'YRIGOYEN Y PUNTA QUBRACHO', 'PUERTO GENERAL SAN MARTIN'),
    (3, '3', 'CARGILL SACI', '30506792165', '3413269645', 'juan_osella@cargill.com', 'SOLIS 822', 'VILLA GOBERNADOR GALVEZ'),
    (4, '4', 'CARGILL SACI', '30506792165', '', '', 'LUIS RAUL MAZA 35', 'BERNARDO LARROUDE'),
    (5, '5', 'JULIO ALVAREZ', '30716236990', '', '', 'BS AS 1122', 'PUERTO GENERAL SAN MARTIN'),
    (6, '6', 'Terminal 6 s.a', '30615829699', '', '', 'Hipolito Yrigoyen y Costa Del', 'PUERTO GENERAL SAN MARTIN'),
    (7, '7', 'ACOSTA SERVICIOS SRL', '30718686217', '', '', 'GARAY 1021', 'PUERTO GENERAL SAN MARTIN'),
    (8, '8', 'SILC SERVICIOS SRL', '30717824594', '', '', '', ''),
    (9, '9', 'T6 INDUSTRIAL S.A', '33689206099', '', '', 'Hipolito Yrigoyen y Gral. Luci', 'PUERTO GENERAL SAN MARTIN'),
    (10, '10', 'PV SERVICIOS SRL', '30716598205', '', '', '', ''),
    (11, '11', 'SAO CLIMA SRL', '30715472313', '', '', 'GRAL PAZ 344', 'CAPITAN BERMUDEZ'),
    (12, '12', 'SOSA SERVICIOS', '30716922150', '', '', 'JOSE PEDRONI 367', 'PUERTO GENERAL SAN MARTIN'),
    (13, '13', 'VICENTIN SAIC', '30500959629', '', '', 'RUTA AO12 KM 64', 'SAN LORENZO'),
    (14, '14', 'CARGILL SACI AMERICA', '30506792165', '', '', 'RUTA 33 KM 386', 'AMERICA')
ON CONFLICT (codigo) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    cuit = EXCLUDED.cuit,
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
