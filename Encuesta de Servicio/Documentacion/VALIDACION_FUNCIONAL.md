# Validación funcional antes de publicar

1. Confirmar credenciales, permisos y DSN de Athena.
2. Comparar el total de filas actualizado con la ejecución documentada (1.878.756 como referencia histórica, no como meta fija).
3. Validar que todos los registros cargados tengan `nombre_encuesta` relacionado con SERVICIO.
4. Validar por período una muestra de votos 1 a 5 contra SQL.
5. Confirmar con el área funcional si notas 6 y 7 deben excluirse del neto institucional.
6. Comparar `Inscritos` contra un `COUNT(DISTINCT estudiante)` de SFRSTCR con estado `RE/RW`, por período y NRC.
7. Confirmar que la tabla de inscripción conserva los demás estados para auditoría, pero no los incorpora al denominador.
8. Verificar que Pregrado, Advance y Postgrado solo expongan períodos desde 202400 en el modelo.
9. Confirmar que `id_estudiante` sea un SHA-256 y que no existan RUT, nombres o correos en las tablas cargadas.
10. Probar la granularidad usando `periodo + NRC + encuesta + pregunta + secuencia`.
11. Revisar áreas normalizadas y glosas de encuestas con errores de catálogo.
12. Probar filtros, menú, tooltip del encabezado, interacciones, exportación, accesibilidad y contraste.
13. Investigar cualquier tasa superior a 100 % por duplicidad de encuestas o diferencias de población.
14. Guardar, cerrar y volver a abrir el PBIP después de actualizar.
15. Validar publicación, gateway y RLS si se incorpora seguridad por usuario.
