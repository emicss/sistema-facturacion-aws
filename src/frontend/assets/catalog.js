import {request,catalog} from './api.js';
import {esc,badge,money,button,table,select,choices,field,pairs,modal,modalForm,dialog,notice} from './ui.js';

const groups = {
  'Infraestructura cloud':'region_aws_default arquitectura_cpu memoria_ram_gb vcpus almacenamiento_gb tipo_almacenamiento ancho_banda_gbps ip_publica_dedicada version_software tiempo_aprovisionamiento_min',
  'SLA y resiliencia':'sla_disponibilidad_porc tiempo_respuesta_soporte_hrs soporte_24_7 nivel_soporte multiaz_habilitado backup_automatico_horas rpo_minutos rto_minutos',
  'Seguridad y normativa':'cifrado_en_reposo algoritmo_cifrado cifrado_en_transito cumplimiento_pci_dss cumplimiento_iso27001 cumplimiento_soc2 retencion_logs_dias waf_incluido',
  'Comercial y fiscal':'precio_unitario aplica_retencion clave_prod_serv_sat clave_unidad_sat moneda tipo_facturacion ciclo_cobro descuento_maximo_porc plazo_minimo_meses penalizacion_cancelacion_porc objeto_impuesto_sat unidad_medida_sat costo_operativo_estimado',
  'Operación y métricas':'activo actualizado_en margen_ganancia_porc consumo_kwh_estimado limite_peticiones_mes responsable_tecnico'
};
async function detail(id,ctx) {
  const [{servicio},{caracteristicas}]=await Promise.all([request('/servicios/'+id),request('/servicios/'+id+'/caracteristicas')]);
  if (!ctx.active()) return;
  const sections={'Identificación':{},...Object.fromEntries(Object.keys(groups).map(k=>[k,{}]))};
  for (const [key,value] of Object.entries(servicio)) {
    const group=Object.keys(groups).find(k=>groups[k].split(' ').includes(key)) || 'Identificación';
    sections[group][key]=value;
  }
  modal(servicio.nombre_servicio,Object.entries(sections).map(([name,data],i)=>
    '<details '+(i===0?'open':'')+'><summary>'+esc(name)+'</summary>'+pairs(data)+'</details>').join('')+
    '<details><summary>Características configuradas</summary>'+table(['Característica','Valor','Unidad'],caracteristicas.map(x=>[x.nombre_caracteristica,x.valor_configurado,x.unidad_medida].map(esc)))+'</details>');
}
export async function services(el,ctx) {
  const rows=await catalog();
  const categories=[...new Set(rows.map(x=>x.categoria))].sort();
  let page=0;
  el.innerHTML='<div class="section-head"><h2>Servicios disponibles <small>'+rows.length+'</small></h2>'+(ctx.admin?button('bulk','Asignación masiva'):'')+'</div><div class="filters"><label>Buscar servicio<input type="search" placeholder="Nombre o código"></label>'+select('category','Categoría', [['','Todas las categorías'],...choices(categories)])+'</div><div class="results"></div>';
  const search=el.querySelector('input'), category=el.querySelector('select');
  function render() {
    const query=search.value.trim().toLocaleLowerCase();
    const filtered=rows.filter(x=>(!category.value || x.categoria===category.value) && (x.nombre_servicio+' '+x.codigo_interno).toLocaleLowerCase().includes(query));
    const slice=filtered.slice(page*12,page*12+12);
    el.querySelector('.results').innerHTML=table(['Servicio','Categoría','Tarifa MXN','Acciones'],slice.map(x=>[
      '<small>'+esc(x.codigo_interno)+'</small><strong>'+esc(x.nombre_servicio)+'</strong>',badge(x.categoria),money(x.precio_unitario),
      button('detail','Ficha técnica',x.id_servicio)+(ctx.issue?button('add','Al carrito',x.id_servicio):'')+(ctx.finance?button('rate','Tarifa',x.id_servicio):'')
    ]),'No se encontraron servicios.')+'<footer>'+esc(filtered.length)+' servicios <span>'+(page?button('prev','Anterior'):'')+(filtered.length>(page+1)*12?button('next','Siguiente'):'')+'</span></footer>';
  }
  render();
  el.oninput=()=>{page=0;render()};
  ctx.actions(el,async (action,id)=>{
    if (action==='prev' || action==='next') {page+=action==='prev'?-1:1;render();return}
    if (action==='detail') return detail(id,ctx);
    const row=rows.find(x=>String(x.id_servicio)===id);
    if (action==='add' && ctx.issue) {
      const cart=await request('/carrito');
      if (!ctx.active()) return;
      const current=cart.items.find(x=>String(x.id_servicio)===id);
      modalForm(row.nombre_servicio,field('cantidad','Cantidad total en el carrito','number','min="0.01" max="99999999.99" step="0.01" value="'+esc(current?.cantidad ?? 1)+'"'),'Guardar en carrito',async data=>{
        await request('/carrito/items','POST',{id_servicio:Number(id),cantidad:Number(data.cantidad)});
        dialog.close(); notice('Cantidad guardada en el carrito.'); await ctx.count();
      });
    }
    if (action==='rate' && ctx.finance) modalForm('Ajustar tarifa', '<p>'+esc(row.nombre_servicio)+'</p>'+field('nuevo_precio','Nueva tarifa (MXN)','number','min="0" step="0.01" value="'+esc(row.precio_unitario)+'"')+field('motivo','Motivo del ajuste','text','minlength="5" maxlength="200"'),'Actualizar tarifa',async data=>{
      await request('/servicios/'+id+'/tarifa','PUT',{...data,nuevo_precio:Number(data.nuevo_precio)});
      dialog.close(); notice('Tarifa actualizada y auditada.'); await ctx.refresh();
    });
    if (action==='bulk' && ctx.admin) {
      const {caracteristicas}=await request('/caracteristicas');
      if (!ctx.active()) return;
      modalForm('Asignación por categoría',select('categoria','Categoría',choices(categories))+select('id_caracteristica','Característica',caracteristicas.map(x=>[x.id_caracteristica,x.nombre_caracteristica]))+field('valor_configurado','Valor para todos los servicios de la categoría'),'Aplicar a la categoría',async data=>{
        const res=await request('/servicios/asignar-caracteristicas-masivas','POST',{...data,id_caracteristica:Number(data.id_caracteristica)});
        modal('Asignación completada',pairs(res.resultado || {mensaje:res.mensaje}));
      });
    }
  });
}
