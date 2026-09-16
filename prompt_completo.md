# 📑 Especificación y Prompt Maestro Completo: Sistema de Gestión de Presupuestos — SG MONTAJES SRL

Documento integral y prompt maestro consolidado con todos los requerimientos, reglas de negocio, flujos de trabajo, esquema de datos, arquitectura y módulos implementados para la plataforma web de **SG MONTAJES SRL (Ingeniería & Montajes Industriales)**.

---

## 🏢 1. Identidad y Propósito del Sistema

- **Empresa**: SG MONTAJES SRL — Ingeniería & Montajes Industriales • Obras Eléctricas y Mecánicas
- **Objetivo**: Sistema web empresarial para la gestión integral de cotizaciones comerciales, presupuestos técnicos, seguimiento y certificación de avances de obra, control estricto de facturación proporcional y reportes gerenciales en tiempo real.
- **Acceso en Producción**: Despliegue en GitHub Pages / Supabase Cloud.
- **Identidad Gráfica**: Esquema corporativo Boca Juniors (Azul Profundo `#00529F` y Dorado/Ámbar `#F3B229`), Glassmorphism compacto de alta densidad y elegancia ejecutiva.

---

## ⚙️ 2. Arquitectura y Stack Tecnológico

- **Frontend**: HTML5 Semántico + Vanilla JavaScript (ES6+ modular, reactivo, sin dependencias externas pesadas) + CSS3 Glassmorphism compacto y responsivo.
- **Base de Datos y Sincronización en Tiempo Real**: Supabase (PostgreSQL 15 + Supabase Realtime Channels) sincronizado bidireccionalmente con `localStorage` y catálogos estáticos compilados (`clientes_db.js`, `condiciones_db.js`, `vendedores_db.js`, `presupuestos_catalog_db.js`).
- **Despacho Oficial de Correos Electrónicos**: Despacho automático y silencioso en segundo plano desde la casilla institucional `cotizaciones@sgmontajes.com.ar`, con compilación instantánea de PDF oficial y adjunto directo.
- **Diseño Adaptativo y Compacto**: 100% responsivo para celulares, tablets, computadoras portátiles y monitores de escritorio con densidad de información optimizada para evitar scrolls excesivos.

---

## ⚡ 3. Gestión de Rubros Industriales

El sistema opera bajo dos rubros principales totalmente diferenciados con correlatividades separadas:

1. **⚡ Presupuesto Eléctrico (`102-ELEC-XXXX`)**:
   - Cotización de montajes eléctricos industriales, tableros de potencia y comando, tendido de bandejas portacables, cableados de fuerza motriz, iluminación industrial y cálculo de horas hombre técnicas.
   - Catálogo de materiales eléctricos y tarifario de mano de obra especializada con numeración correlativa estricta (`ELE-001`, `ELE-002`...).

2. **⚙️ Presupuesto Mecánico (`101-MEC-XXXX`)**:
   - Cotización de montajes mecánicos pesados, estructuras metálicas, cañerías industriales, soldadura calificada, piping y mecanizados.
   - Ficha técnica completa de oferta: Denominación de la Obra/Instalación, Planta, Proveedor (SG MONTAJES SRL), Fecha de Oferta, Validez, Plazo de Ejecución, Fechas Estimadas de Inicio/Fin, N° OT, Propuesta Técnica, Personal Asignado y Cláusula de Exclusiones.

- **Conmutador de Rubro Superior**: Selector en la barra de navegación para alternar instantáneamente entre vistas Eléctrica y Mecánica sin recargar la página.
- **Denominación del Servicio Limpia**: En ambas modalidades, el campo "Denominación del Servicio" se presenta vacío por defecto listo para la carga específica de la obra.

---

## 🔄 4. Flujo y Reglas de Estados Comerciales

### 4.1. Los 4 Únicos Estados Comerciales del Presupuesto
El ciclo de vida comercial de un presupuesto opera estrictamente bajo **4 únicos estados comerciales**:

1. `📤 Enviado sin OC` *(Nivel 1 - Color Celeste/Azul `#38bdf8`)*: Presupuesto emitido y entregado formalmente al cliente por correo o mano, a la espera de confirmación.
2. `⏳ Aprobado sin OC` *(Nivel 2 - Color Ámbar `#fef08a`)*: Aprobación verbal/preliminar del cliente previa a la emisión de la orden de compra.
3. `✅ Aprobado con OC` *(Nivel 3 - Color Verde Esmeralda `#6ee7b7`)*: Aprobación formal adjudicada. **Exige ingreso obligatorio del Número de Orden de Compra (OC)**.
4. `❌ Rechazado` *(Estado Terminal - Color Rosa/Rojo `#fda4af`)*: Oferta desestimada por el cliente. **Exige ingreso obligatorio del motivo de rechazo**.

### 4.2. Derivación a "Registros de Facturación"
- **Separación de Conceptos**: La facturación (`Facturado Parcial` y `Facturado Total`) **NO forma parte del desplegable de estados comerciales del presupuesto**. El presupuesto adjudicado permanece comercialmente como `Aprobado con OC`.
- **Módulo "Registros de Facturación" (`tpl-facturacion`)**: Es el espacio exclusivo donde van a parar los presupuestos y comprobantes **una vez que están aprobados con OC** para su control administrativo, clasificándose automáticamente según su cobranza real:
  - 🔴 **Pendiente de Facturar**: 0% facturado.
  - 🟡 **Facturación Parcial**: >0% y <100% facturado.
  - 🟢 **Facturación Total**: 100% facturado.

### 4.3. 🚫 Prohibición Estricta de Retroceso de Estados
- **Los estados no pueden volver atrás**: Un presupuesto que ha alcanzado un nivel superior no puede retroceder a uno anterior (por ejemplo, `Aprobado con OC` no puede volver a `Aprobado sin OC` ni `Enviado sin OC`).
- **En el selector desplegable**: Las opciones inferiores a la actual aparecen deshabilitadas con el indicador `🚫`.

### 4.4. 🔄 Reactivación de Presupuestos Rechazados ("Revivir")
- **Acción exclusiva en presupuestos rechazados**: En la vista de "Rechazo de Presupuesto", el botón verde **`Revivir`** permite reactivar la oferta.
- **Cuadro de diálogo y confirmación exacta**:
  > `¿Estás seguro de que deseas revivir este presupuesto? Se restaurará su estado a "Pendiente" y sus ítems se actualizarán con los precios actuales del tarifario.`
- **Acciones automáticas al confirmar**:
  1. **Restauración de Estado**: Pasa automáticamente al estado comercial `"Enviado sin OC"`, reincorporándose a la tabla activa de seguimiento.
  2. **Actualización de Precios Vigentes**: Cada artículo/ítem del presupuesto consulta en tiempo real el tarifario activo (mecánico o eléctrico) y refresca su precio unitario con el valor actual de la base de datos.
  3. **Recálculo de Totales**: Se recalculan los subtotales (`cantidad * precio unitario`) y el importe total general del presupuesto.
  4. **Limpieza de Motivo de Rechazo**: Se eliminan los motivos de rechazo previos registrados.
  5. **Persistencia y Refresco Inmediato**: Se guardan los cambios en el almacenamiento local y Supabase, se muestra la notificación de éxito y se actualiza la grilla en pantalla.

---

## 🏗️ 5. Avance de Obra y Control de Facturación

### 5.1. Certificación de Avance de Obra
- Registro de hitos de avance con:
  - **% de Avance** (ingresado con coma decimal `,`, tope estricto del 100% acumulado).
  - **Fecha del Hito**.
  - **N° de Documento / Acta de Certificación**.
  - **Detalle de los trabajos ejecutados**.
- **Cálculo Automático en Pesos**: Determina en tiempo real el monto valorizado en pesos del avance ingresado respecto al monto total del presupuesto.
- **Notificación Automática por Email**: Disparo de correo de alerta a Facturación (`📄 Notificación de Avance de Obra`) cada vez que se certifica un nuevo hito.

### 5.2. Certificación Desglosada por Proyecto (por Títulos)
- **Acceso Exclusivo y Centralizado**: Botón **`Avance de Proyecto`** ubicado en el encabezado del modal de *Avance de Obra*.
- **Validación Estricta de Tope Infranqueable del 100%**:
  - Ningún rubro o título puede superar el 100% de avance acumulado.
  - El sistema calcula dinámicamente el saldo máximo disponible (`100% - acumulado previo`). Si el operador intenta ingresar un valor superior, el sistema bloquea la entrada y ajusta automáticamente al tope permitido.
  - Los conceptos que alcanzan el 100% acumulado se deshabilitan y se identifican con la insignia verde **`✓ 100% Completado`**.
- **Sincronización Automática**: Actualización en tiempo real del historial financiero y la barra de progreso acumulado.

### 5.3. Reglas de Facturación Proporcional
1. **Tope por Avance**: El `% Facturado` **nunca puede superar el % de Avance de Obra realizado**.
2. **Avance 0%**: Si el avance de obra es `0%`, está estrictamente prohibido ingresar porcentaje de facturación o cambiar el estado a `Facturado`.
3. **Facturado Total**: Para marcar un presupuesto como `Facturado Total` (100%), la obra debe tener certificado previamente el **100% de Avance de Obra**.
4. **Límite Absoluto**: Ningún porcentaje (ni de avance ni de facturación) puede exceder el **100%**.
5. **Aviso Destacado "FALTA FACTURAR"**: Si existe avance físico certificado superior al porcentaje facturado, el sistema muestra en la grilla una alerta llamativa con el monto exacto listo para facturar.

---

## 📑 6. Visualización y Formato Oficial de Comprobantes

### 6.1. Selector Dinámico de Presentación (3 Formatos)
Al consultar un presupuesto con el botón **[ 👁️ Ver ]**, el usuario puede alternar instantáneamente entre 3 modalidades de comprobante:
1. 🏗️ **Comprobante por Proyecto**: Agrupa y consolida los conceptos por proyecto u obra específica, presentando el alcance global, los hitos clave y la consolidación económica general.
2. 📄 **Comprobante Detallado**: Muestra la planilla técnica completa con el desglose ítem por ítem, rubros, cantidades, unidades de medida, precios unitarios y subtotales.
3. 📋 **Comprobante Resumido**: Presenta la cotización condensada en una sola línea ejecutiva con la denominación del trabajo, cantidad global, subtotal neto, I.V.A. (21%) e importe total final.

### 6.2. Estándares Visuales de Comprobante Oficial
- **Membrete Corporativo**: Datos fiscales completos (SG MONTAJES SRL, CUIT 30-71602466-7, Ingresos Brutos, IVA Responsable Inscripto).
- **Ficha de Cliente en Celdas Individuales**: Datos de obra y cliente enmarcados en recuadros rectangulares independientes con esquinas redondeadas.
- **Marca de Agua Centralizada**: Logotipo oficial de SG MONTAJES centrado e inclinado detrás de la grilla de ítems con opacidad calibrada para garantizar lectura clara.
- **Encabezados Transparentes**: Los encabezados del comprobante cuentan con fondo traslúcido para no obstruir la marca de agua.
- **Etiquetado de Totales**: Todas las etiquetas de monto neto final se rotulan estrictamente como `TOTAL:` (eliminando sufijos redundantes como "Total Neto Presupuesto").

---

## 📧 7. Despacho Oficial de Cotizaciones por Email

- **Despacho Automático en Segundo Plano**: Al pulsar "Enviar Cotización Oficial", el sistema compila el archivo PDF oficial con logotipo e ítems y lo despacha de forma silenciosa e inmediata desde `cotizaciones@sgmontajes.com.ar`.
- **Destinatarios Consolidados**: Botón rápido `[+ Agregar Todos los Destinatarios]` para sumar cliente, cotizaciones, administración y facturación con un solo toque.
- **Chips Interactivos**: Selección y remoción ágil de destinatarios TO y CC.
- **Actualización de Estado y Sincronización**: Al enviar, el presupuesto actualiza automáticamente su estado a `Enviado sin OC` (en color celeste/azul corporativo) y sincroniza los cambios en la nube.

---

## 📊 8. Reportes Gerenciales e Integración Excel

### 8.1. Reporte Impreso Oficial Multi-Tabla
- Estructura limpia y ejecutiva sin páginas en blanco iniciales.
- **Tabla 1: Resumen por Estado Comercial**: Cantidad de presupuestos, subtotal neto, IVA y total por cada estado.
- **Tabla 2: Resumen Consolidado por Cliente**: Agrupación por cliente con fila de **TOTAL GENERAL CLIENTES**.
- **Tabla 3: Detalle de Cotizaciones**: Listado individual completo con ID, fecha, rubro, cliente, obra, estado, % avance y total con IVA.

### 8.2. Exportación Nativa a Excel (`.xls`)
- Generación nativa con membrete institucional, fecha/hora exacta y formato numérico monetario (`$ #.##0,00`) y porcentual real.

---

## 🛡️ 9. Seguridad, UX y Navegación Universal

- **Segregación Estricta Ver vs Editar**:
  - `[ 👁️ Ver ]`: Modo solo lectura para consulta visual y generación de comprobantes.
  - `[ ✏️ Editar ]`: Modo edición con formulario activo y actualización de ítems.
- **Edición de Precios por Matriz de Permisos**: La modificación de precios unitarios está vinculada a los permisos del usuario (`menu-ingresar-edit-price` / `edit-precios`).
- **Navegación Universal con Tecla Escape (`Esc`)**: Cierre inmediato de cualquier modal abierto y retorno limpio a la vista anterior.
- **Acceso y Salida Limpia**: Login simplificado con botón "Ingresar" y cierre de sesión seguro mediante botón "Salir" (`#logout-btn`).

---

*Documento maestro actualizado y consolidado — SG MONTAJES SRL © 2026*
