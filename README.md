# 🛰️ GeoColombia Ultra - GPS Topográfico Profesional

Aplicación móvil desarrollada en Flutter para topografía, georreferenciación y navegación técnica en Colombia. Diseñada para operar en entornos sin conexión y garantizar precisión de hardware ignorando la triangulación celular.

## ✨ Características Principales

*   **📍 GPS Hardware Puro:** Algoritmo que fuerza el uso del chip GNSS y descarta señales de red (precisión < 10m).
*   **🗺️ Mapas Offline:** Sistema de caché inteligente y descarga de zonas completas de Colombia (Zoom 7-9).
*   **📡 Modo Dual:** Alternancia entre Mapa de Calles (OSM) y Satelital (Esri World Imagery).
*   **📷 Cámara Técnica:** Generación de evidencia fotográfica con marca de agua (Fecha, Coordenadas, Altitud y Precisión) y mira telescópica.
*   **🔍 Controles Avanzados:** Zoom manual y monitoreo de señal satelital en tiempo real.
*   **🎨 UI Glassmorphism:** Interfaz moderna, oscura y semitransparente.

## 🛠️ Tecnologías Usadas

*   **Flutter & Dart**
*   `geolocator`: Control de hardware GPS de bajo nivel.
*   `flutter_map`: Renderizado de mapas.
*   `dio` & `dio_cache_interceptor`: Descarga y persistencia de mapas offline.
*   `gal` & `image`: Procesamiento de imágenes y guardado en galería.

## 🚀 Instalación

1.  Clonar el repositorio:
    ```bash
    git clone https://github.com/TU_USUARIO/GeoColombia-App.git
    ```
2.  Instalar dependencias:
    ```bash
    flutter pub get
    ```
3.  Ejecutar en dispositivo físico (Requerido para GPS):
    ```bash
    flutter run
    ```

## ⚠️ Requisitos

*   Android 10 o superior (Recomendado para soporte de Foreground Service).
*   Permisos de Ubicación "Precisos" y "Todo el tiempo".

---
Desarrollado con ❤️ para la ingeniería colombiana.