# Consola de facturación CloudTech

Desde la raíz del repositorio, ejecuta `python3 -m http.server 8080 --directory src/frontend` y abre `http://localhost:8080`. Las cuentas de prueba están en `docs/especificaciones_frontend.md`.

La consola carga la URL de API Gateway desde `assets/config.json`. Cambia `apiBase` para apuntar a otro entorno. Si FastAPI sirve el frontend en su ruta raíz, puedes usar un valor vacío para consultar la API del mismo origen. Para desarrollo local también se admite HTTP en localhost.

Para publicar, copia el contenido completo de `src/frontend` (index.html y assets/) a tu origen estático. Sirve los archivos con sus tipos MIME y usa HTTPS, por ejemplo con CloudFront delante de S3. La navegación usa fragmentos de URL y permite recargar cualquier vista. El navegador ejecuta los módulos directamente, sin compilación ni dependencias de producción.

La sesión se conserva en la pestaña. Si se interrumpe una emisión o un abono, la consola ofrece reintentar el envío original con su misma clave. El carrito se recupera de DynamoDB. El comprobante presenta los importes calculados por RDS. La auditoría pagina en el navegador los hasta 50 eventos devueltos por el endpoint.
