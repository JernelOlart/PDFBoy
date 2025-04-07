//
//  ContentView.swift
//  PDFBoy
//
//  Created by Elian Hernández Olarte on 05/04/25.
//
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var textoSalida = "Arrastra archivos PDF aquí o haz clic para seleccionar"
    @State private var cargando = false
    @State private var estadoInstalacion: EstadoInstalacion = .verificando
    @State private var archivosProcesados: [ArchivoProcesado] = []
    @State private var nivelCompresion: NivelCompresion = .medio
    @State private var ubicacionGuardado: UbicacionGuardado = .mismaCarpeta
    @State private var abrirDespuesCompresion = true
    @State private var mostrarAlertaInstalacion = false
    @State private var mostrarPanelAcercaDe = false
    @State private var mostrarAlertaCompresion = false
    @State private var mensajeAlertaCompresion = ""
    @State private var pythonInstalado = false
    @State private var ghostscriptInstalado = false
    @StateObject private var colaArchivos = ColaProcesamientoArchivos()
    
    enum EstadoInstalacion: Equatable {
        case verificando, instalando, listo, fallido(String)
    }
    
    enum NivelCompresion: String, CaseIterable, Identifiable {
        case bajo = "Básico (rápido)"
        case medio = "Avanzado (recomendado)"
        case alto = "Ultra (Ghostscript)"
        var id: Self { self }
    }
    
    enum UbicacionGuardado: String, CaseIterable, Identifiable {
        case mismaCarpeta = "Misma carpeta"
        case escritorio = "Escritorio"
        case documentos = "Documentos"
        var id: Self { self }
    }
    
    struct ArchivoProcesado: Identifiable {
        let id = UUID()
        let urlOriginal: URL
        let urlComprimido: URL
        let tamañoOriginal: Int64
        let tamañoComprimido: Int64
        let porcentajeReduccion: Double
        let nivelCompresion: NivelCompresion
        let fechaProcesamiento: Date
        
        var fechaFormateada: String {
            let formateador = DateFormatter()
            formateador.dateStyle = .short
            formateador.timeStyle = .short
            return formateador.string(from: fechaProcesamiento)
        }
    }
    
    private let scriptPython = """
    import os
    import sys
    from PyPDF2 import PdfReader, PdfWriter
    import subprocess
    import zlib
    import io

    def verificar_ghostscript():
        try:
            subprocess.run(["gs", "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            return True
        except:
            return False

    def comprimir_con_pypdf(ruta_entrada, ruta_salida, calidad):
        try:
            with open(ruta_entrada, 'rb') as file:
                reader = PdfReader(file)
                writer = PdfWriter()
                for page in reader.pages:
                    # Comprimir contenido antes de agregar
                    if '/Contents' in page:
                        contents = page['/Contents']
                        if isinstance(contents, list):
                            new_contents = []
                            for stream in contents:
                                if hasattr(stream, 'get_data'):
                                    try:
                                        data = stream.get_data()
                                        compressed = zlib.compress(data, level=9)
                                        new_stream = io.BytesIO(compressed)
                                        new_contents.append(new_stream)
                                    except:
                                        new_contents.append(stream)
                            page.__setitem__('/Contents', new_contents)
                        else:
                            try:
                                data = contents.get_data()
                                compressed = zlib.compress(data, level=9)
                                new_stream = io.BytesIO(compressed)
                                page.__setitem__('/Contents', new_stream)
                            except:
                                pass
                    page.compress_content_streams()
                    writer.add_page(page)
                
                with open(ruta_salida, 'wb') as output_file:
                    writer.write(output_file)
            
            original = os.path.getsize(ruta_entrada)
            comprimido = os.path.getsize(ruta_salida)
            
            if comprimido >= original:
                os.remove(ruta_salida)
                shutil.copy(ruta_entrada, ruta_salida)
                return original, original
            
            return original, comprimido
        except Exception as e:
            if verificar_ghostscript():
                return comprimir_con_ghostscript(ruta_entrada, ruta_salida)
            raise e

    def comprimir_con_ghostscript(ruta_entrada, ruta_salida):
        try:
            comando = [
                "gs", "-sDEVICE=pdfwrite",
                "-dCompatibilityLevel=1.4",
                "-dPDFSETTINGS=/screen",  # Máxima compresión
                "-dNOPAUSE", "-dQUIET", "-dBATCH",
                "-dColorConversionStrategy=/sRGB",
                "-dDownsampleColorImages=true",
                "-dColorImageDownsampleType=/Bicubic",
                "-dColorImageResolution=72",  # 72 DPI para pantallas
                "-dGrayImageDownsampleType=/Bicubic",
                "-dGrayImageResolution=72",
                "-dMonoImageDownsampleType=/Bicubic",
                "-dMonoImageResolution=72",
                "-dAutoRotatePages=/None",
                "-sOutputFile=" + ruta_salida,
                ruta_entrada
            ]
            
            resultado = subprocess.run(comando, capture_output=True, text=True, check=True)
            return os.path.getsize(ruta_entrada), os.path.getsize(ruta_salida)
        except Exception as e:
            raise Exception(f"Error en Ghostscript: {str(e)}")

    def main():
        if len(sys.argv) < 4:
            print("ERROR:Uso: python script.py entrada.pdf salida.pdf [bajo|medio|alto]")
            sys.exit(1)
            
        ruta_entrada, ruta_salida, calidad = sys.argv[1], sys.argv[2], sys.argv[3].lower()
        
        try:
            if calidad == 'alto':
                if not verificar_ghostscript():
                    print("ADVERTENCIA:Ghostscript no instalado. Usando compresión media")
                    calidad = 'medio'
                else:
                    original, comprimido = comprimir_con_ghostscript(ruta_entrada, ruta_salida)
                    reduccion = 100 - (comprimido / original) * 100 if original > 0 else 0
                    print(f"EXITO:{original}:{comprimido}:{reduccion:.2f}:{calidad}")
                    return
            
            original, comprimido = comprimir_con_pypdf(ruta_entrada, ruta_salida, calidad)
            reduccion = 100 - (comprimido / original) * 100 if original > 0 else 0
            
            if reduccion <= 0:
                print(f"ADVERTENCIA:{original}:{comprimido}:0:{calidad}:Compresión no efectiva")
            else:
                print(f"EXITO:{original}:{comprimido}:{reduccion:.2f}:{calidad}")
        except Exception as e:
            print(f"ERROR:{str(e)}")

    if __name__ == "__main__":
        main()
    """

    var body: some View {
        NavigationView {
            barraLateral
            contenidoPrincipal
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { mostrarPanelAcercaDe.toggle() }) {
                        Label("Acerca de PDFBoy", systemImage: "info.circle")
                    }
                    Button(action: verificarDependencias) {
                        Label("Verificar Dependencias", systemImage: "checkmark.shield")
                    }
                } label: {
                    Label("Más Opciones", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Instalación Necesaria", isPresented: $mostrarAlertaInstalacion) {
            Button("Instalar Todo") { instalarDependencias() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se requieren Python 3, PyPDF2 y Ghostscript para compresión óptima")
        }
        .alert("Resultado", isPresented: $mostrarAlertaCompresion) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mensajeAlertaCompresion)
        }
        .sheet(isPresented: $mostrarPanelAcercaDe) {
            panelAcercaDe
        }
        .onAppear(perform: verificarDependencias)
        .frame(minWidth: 800, minHeight: 600)
    }

    private var barraLateral: some View {
        List {
            Section("Acciones") {
                Button(action: seleccionarArchivosPDF) {
                    Label("Añadir PDFs", systemImage: "plus")
                }
                Button(action: procesarCola) {
                    Label("Comprimir (\(colaArchivos.cantidad))", systemImage: "arrow.down.doc")
                }
                .disabled(colaArchivos.estaVacia || cargando)
                
                if !archivosProcesados.isEmpty {
                    Button(action: limpiarTodo) {
                        Label("Limpiar Todo", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section("Configuración") {
                Picker("Nivel:", selection: $nivelCompresion) {
                    ForEach(NivelCompresion.allCases) { nivel in
                        Text(nivel.rawValue).tag(nivel)
                    }
                }
                Picker("Guardar en:", selection: $ubicacionGuardado) {
                    ForEach(UbicacionGuardado.allCases) { ubicacion in
                        Text(ubicacion.rawValue).tag(ubicacion)
                    }
                }
                Toggle("Abrir después", isOn: $abrirDespuesCompresion)
            }
            
            Section("Estado") {
                HStack {
                    Image(systemName: pythonInstalado ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(pythonInstalado ? .green : .red)
                    Text("Python 3 + PyPDF2")
                }
                HStack {
                    Image(systemName: ghostscriptInstalado ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(ghostscriptInstalado ? .green : .red)
                    Text("Ghostscript")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 250)
    }

    private var contenidoPrincipal: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .edgesIgnoringSafeArea(.all)
            if archivosProcesados.isEmpty {
                vistaEstadoVacio
            } else {
                listaResultados
            }
            if cargando {
                overlayCargando
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: manejarArrastre)
    }

    private var vistaEstadoVacio: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            Text(textoSalida)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()
            Text("Nivel: \(nivelCompresion.rawValue)")
                .foregroundColor(.secondary)
            if !colaArchivos.estaVacia {
                Text("\(colaArchivos.cantidad) archivo(s) en cola")
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listaResultados: some View {
        List {
            ForEach(archivosProcesados) { archivo in
                filaArchivo(archivo)
                    .contextMenu {
                        Button(action: { mostrarEnFinder(archivo.urlComprimido) }) {
                            Label("Mostrar en Finder", systemImage: "folder")
                        }
                        Button(action: { abrirArchivo(archivo.urlComprimido) }) {
                            Label("Abrir Archivo", systemImage: "doc.viewfinder")
                        }
                        Divider()
                        Button(role: .destructive) {
                            eliminarDeHistorial(archivo)
                        } label: {
                            Label("Eliminar del historial", systemImage: "trash")
                        }
                    }
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var overlayCargando: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                Text("Procesando archivos...")
                    .font(.headline)
                if colaArchivos.cantidad > 1 {
                    Text("\(colaArchivos.cantidad - colaArchivos.indiceProcesamiento) restantes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(30)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(15)
        }
    }

    private var panelAcercaDe: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
            Text("PDFBoy")
                .font(.largeTitle)
                .bold()
            Text("Compresor PDF v2.1")
                .font(.title2)
                .foregroundColor(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Mejoras clave:")
                    .font(.headline)
                Text("• Compresión zlib nivel 9")
                Text("• Soporte Ghostscript 10.5")
                Text("• Fallback automático")
                Text("• Optimización de streams PDF")
                Text("• Reducción de DPI a 72 para pantallas")
            }
            Divider()
            Text("© \(Calendar.current.component(.year, from: Date()))")
                .font(.footnote)
            Button("Cerrar") {
                mostrarPanelAcercaDe = false
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
    }

    private func filaArchivo(_ archivo: ArchivoProcesado) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(archivo.urlOriginal.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(archivo.porcentajeReduccion, specifier: "%.1f")%")
                    .foregroundColor(colorReduccion(archivo.porcentajeReduccion))
                    .bold()
                Text(archivo.nivelCompresion.rawValue.components(separatedBy: " ").first ?? "")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Original: \(formatearTamaño(archivo.tamañoOriginal))")
                    .foregroundColor(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                Text("Comprimido: \(formatearTamaño(archivo.tamañoComprimido))")
                    .bold()
                Spacer()
                Text(archivo.fechaFormateada)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: Double(archivo.tamañoComprimido), total: Double(archivo.tamañoOriginal))
                .accentColor(colorReduccion(archivo.porcentajeReduccion))
        }
        .padding(.vertical, 8)
    }

    private func verificarDependencias() {
        estadoInstalacion = .verificando
        cargando = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (tienePython, tienePyPDF, tieneGhostscript) = self.verificarDependenciasSistema()
            DispatchQueue.main.async {
                self.cargando = false
                self.pythonInstalado = tienePython && tienePyPDF
                self.ghostscriptInstalado = tieneGhostscript
                
                if !tienePython || !tienePyPDF {
                    self.mostrarAlertaInstalacion = true
                    self.estadoInstalacion = .fallido("Faltan dependencias esenciales")
                    self.textoSalida = "Python 3 y PyPDF2 requeridos"
                } else {
                    self.estadoInstalacion = .listo
                    if self.nivelCompresion == .alto && !tieneGhostscript {
                        self.textoSalida = "Ghostscript recomendado para compresión Ultra"
                    }
                }
            }
        }
    }

    private func instalarDependencias() {
        estadoInstalacion = .instalando
        cargando = true
        DispatchQueue.global(qos: .utility).async {
            do {
                // Instalar Homebrew
                if self.ejecutarComando("which brew").isEmpty {
                    try self.ejecutarComandoConPermisos("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                    try self.ejecutarComandoConPermisos("echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile")
                    try self.ejecutarComandoConPermisos("eval \"$(/opt/homebrew/bin/brew shellenv)\"")
                }
                
                // Instalar Python y dependencias
                try self.ejecutarComandoConPermisos("brew install python")
                try self.ejecutarComandoConPermisos("python3 -m pip install --upgrade pip")
                try self.ejecutarComandoConPermisos("python3 -m pip install PyPDF2")
                
                // Instalar Ghostscript
                try self.ejecutarComandoConPermisos("brew install ghostscript")
                
                // Verificación final
                let (tienePython, tienePyPDF, tieneGhostscript) = self.verificarDependenciasSistema()
                DispatchQueue.main.async {
                    self.cargando = false
                    self.pythonInstalado = tienePython && tienePyPDF
                    self.ghostscriptInstalado = tieneGhostscript
                    
                    if tienePython && tienePyPDF {
                        self.estadoInstalacion = .listo
                        self.textoSalida = "Dependencias instaladas correctamente"
                        if !tieneGhostscript {
                            self.mensajeAlertaCompresion = "Ghostscript no instalado. Compresión Ultra no disponible"
                            self.mostrarAlertaCompresion = true
                        }
                    } else {
                        self.estadoInstalacion = .fallido("Error de instalación")
                        self.mensajeAlertaCompresion = "Fallo en la instalación de dependencias"
                        self.mostrarAlertaCompresion = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.cargando = false
                    self.estadoInstalacion = .fallido("Error de instalación")
                    self.mensajeAlertaCompresion = "Error durante la instalación: \\(error.localizedDescription)"
                    self.mostrarAlertaCompresion = true
                }
            }
        }
    }

    private func manejarArrastre(proveedores: [NSItemProvider]) -> Bool {
        for proveedor in proveedores {
            proveedor.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { datos, error in
                if let datosURL = datos as? Data,
                   let url = URL(dataRepresentation: datosURL, relativeTo: nil),
                   url.pathExtension.lowercased() == "pdf" {
                    DispatchQueue.main.async {
                        if !self.colaArchivos.archivos.contains(where: { $0.path == url.path }) {
                            self.colaArchivos.agregar(url)
                            self.textoSalida = "\(self.colaArchivos.cantidad) archivo(s) listos"
                        }
                    }
                }
            }
        }
        return true
    }

    private func seleccionarArchivosPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !colaArchivos.archivos.contains(where: { $0.path == url.path }) {
                    colaArchivos.agregar(url)
                }
            }
            textoSalida = "\(colaArchivos.cantidad) archivo(s) listos"
        }
    }

    private func procesarCola() {
        guard !colaArchivos.estaVacia else { return }
        cargando = true
        colaArchivos.indiceProcesamiento = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            let rutaScriptTemp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pdfboy_\(UUID().uuidString).py")
            do {
                try self.scriptPython.write(to: rutaScriptTemp, atomically: true, encoding: .utf8)
                
                for url in self.colaArchivos.archivos {
                    defer { self.colaArchivos.indiceProcesamiento += 1 }
                    let urlSalida = self.determinarURLSalida(para: url)
                    let calidad = self.nivelCompresion == .alto ? "alto" : (self.nivelCompresion == .medio ? "medio" : "bajo")
                    let comando = "python3 \(rutaScriptTemp.path) \"\(url.path)\" \"\(urlSalida.path)\" \(calidad)"
                    
                    let resultado = self.ejecutarComando(comando)
                    DispatchQueue.main.async {
                        if resultado.starts(with: "EXITO") {
                            let partes = resultado.components(separatedBy: ":")
                            if partes.count >= 4 {
                                let original = Int64(partes[1]) ?? 0
                                let comprimido = Int64(partes[2]) ?? 0
                                let reduccion = Double(partes[3]) ?? 0
                                let nivel = self.nivelCompresionFromString(partes[4])
                                
                                let archivoProcesado = ArchivoProcesado(
                                    urlOriginal: url,
                                    urlComprimido: urlSalida,
                                    tamañoOriginal: original,
                                    tamañoComprimido: comprimido,
                                    porcentajeReduccion: reduccion,
                                    nivelCompresion: nivel,
                                    fechaProcesamiento: Date()
                                )
                                self.archivosProcesados.insert(archivoProcesado, at: 0)
                                if self.abrirDespuesCompresion {
                                    NSWorkspace.shared.open(urlSalida)
                                }
                            }
                        } else if resultado.starts(with: "ADVERTENCIA") {
                            self.mensajeAlertaCompresion = "Compresión no efectiva: \\(resultado)"
                            self.mostrarAlertaCompresion = true
                        } else {
                            self.mensajeAlertaCompresion = "Error: \\(resultado)"
                            self.mostrarAlertaCompresion = true
                        }
                    }
                }
                
                try? FileManager.default.removeItem(at: rutaScriptTemp)
                DispatchQueue.main.async {
                    self.colaArchivos.limpiar()
                    self.cargando = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.mensajeAlertaCompresion = error.localizedDescription
                    self.mostrarAlertaCompresion = true
                    self.cargando = false
                }
            }
        }
    }

    private func nivelCompresionFromString(_ string: String) -> NivelCompresion {
        switch string {
        case "alto": return .alto
        case "bajo": return .bajo
        default: return .medio
        }
    }

    private func determinarURLSalida(para urlEntrada: URL) -> URL {
        let nombreBase = urlEntrada.deletingPathExtension().lastPathComponent
        var urlSalida: URL
        
        switch ubicacionGuardado {
        case .mismaCarpeta:
            urlSalida = urlEntrada.deletingLastPathComponent()
        case .escritorio:
            urlSalida = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        case .documentos:
            urlSalida = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        
        urlSalida = urlSalida.appendingPathComponent("\(nombreBase)_comprimido.pdf")
        var contador = 1
        
        while FileManager.default.fileExists(atPath: urlSalida.path) {
            urlSalida = urlSalida.deletingLastPathComponent()
                .appendingPathComponent("\(nombreBase)_comprimido(\(contador)).pdf")
            contador += 1
        }
        
        return urlSalida
    }

    private func limpiarTodo() {
        colaArchivos.limpiar()
        archivosProcesados.removeAll()
        textoSalida = "Arrastra archivos PDF aquí o haz clic para seleccionar"
    }

    private func eliminarDeHistorial(_ archivo: ArchivoProcesado) {
        archivosProcesados.removeAll { $0.id == archivo.id }
    }

    private func mostrarEnFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func abrirArchivo(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func formatearTamaño(_ bytes: Int64) -> String {
        let formateador = ByteCountFormatter()
        formateador.allowedUnits = [.useMB, .useKB]
        formateador.countStyle = .file
        return formateador.string(fromByteCount: bytes)
    }

    private func colorReduccion(_ porcentaje: Double) -> Color {
        switch porcentaje {
        case ..<0: return .red
        case 0..<10: return .gray
        case 10..<30: return .blue
        case 30..<50: return .green
        case 50...: return .purple
        default: return .primary
        }
    }

    private func verificarDependenciasSistema() -> (python: Bool, pypdf2: Bool, ghostscript: Bool) {
        let verificarPython = ejecutarComando("python3 --version")
        let tienePython = verificarPython.contains("Python 3")
        
        let verificarPyPDF = ejecutarComando("python3 -c \"import PyPDF2; print('OK')\"")
        let tienePyPDF = verificarPyPDF.contains("OK")
        
        let verificarGS = ejecutarComando("gs --version")
        let tieneGhostscript = !verificarGS.isEmpty
        
        return (tienePython, tienePyPDF, tieneGhostscript)
    }

    private func ejecutarComando(_ comando: String) -> String {
        let proceso = Process()
        let tuberia = Pipe()
        proceso.standardOutput = tuberia
        proceso.standardError = tuberia
        proceso.arguments = ["-c", comando]
        proceso.launchPath = "/bin/zsh"
        
        do {
            try proceso.run()
            let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
            return String(data: datos, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "ERROR:\(error.localizedDescription)"
        }
    }

    private func ejecutarComandoConPermisos(_ comando: String) throws {
        let proceso = Process()
        proceso.launchPath = "/usr/bin/sudo"
        proceso.arguments = ["/bin/zsh", "-c", comando]
        
        let tuberia = Pipe()
        proceso.standardOutput = tuberia
        proceso.standardError = tuberia
        
        try proceso.run()
        proceso.waitUntilExit()
        
        let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
        if let salida = String(data: datos, encoding: .utf8) {
            print("SALIDA: \\(salida)")
        }
    }
}

class ColaProcesamientoArchivos: ObservableObject {
    @Published private(set) var archivos: [URL] = []
    @Published var indiceProcesamiento = 0
    
    var cantidad: Int { archivos.count }
    var estaVacia: Bool { archivos.isEmpty }
    
    func agregar(_ url: URL) {
        archivos.append(url)
    }
    
    func limpiar() {
        archivos.removeAll()
        indiceProcesamiento = 0
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
