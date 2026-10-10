// Usuarios de muestra del Fixture 2030. Nombres e idiomas son los de la muestra
// de Cassandra; Redis (sesiones) debe referenciar estos mismos IDs. Datos
// ficticios: los emails usan el dominio reservado example.com.
//
// Los IDs tienen el formato de Cassandra (U + 6 digitos). Los usuarios que genera
// el millon de comentarios (U000000 a U099999) no tienen perfil en esta carga.

globalThis.USUARIOS = [
  { _id: "U000001", email: "sofia@example.com",  nombre_usuario: "Sofía",  rol: "fan",       idioma: "es", pais: "AR" },
  { _id: "U000002", email: "mark@example.com",   nombre_usuario: "Mark",   rol: "fan",       idioma: "en", pais: "GB" },
  { _id: "U000003", email: "joao@example.com",   nombre_usuario: "Joao",   rol: "moderador", idioma: "pt", pais: "BR" },
  { _id: "U000004", email: "amelie@example.com", nombre_usuario: "Amélie", rol: "fan",       idioma: "fr", pais: "FR" },
  { _id: "U000005", email: "omar@example.com",   nombre_usuario: "Omar",   rol: "fan",       idioma: "es", pais: "ES" },
  { _id: "U000099", email: "demo@example.com",   nombre_usuario: "demo",   rol: "fan",       idioma: "es", pais: "AR" },
];
