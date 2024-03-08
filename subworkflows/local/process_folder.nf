workflow PROCESS_FOLDER {
    take:
        folder // file: /path/to/samplesheet.csv

    main:

        log.debug "Checking folder..."

        illumina_reads = nanopore_reads = Channel.empty()

        def illumina_files = { file -> file.name.lastIndexOf('_L001').with {it != -1 ? file.name[0..<it] : file.name} }
        Channel.fromFilePairs( params.illumina_search_path, flat: true, illumina_files) | map{ checkReads(it, platform = "illumina") } | set{ illumina_reads }

        def nanopore_files = { file -> file.name.lastIndexOf('_').with {it != -1 ? file.name[0..<it] : file.name} }
        Channel.fromFilePairs( params.nanopore_search_path, flat: true , size: -1, nanopore_files) | map{ checkReads(it, platform = "nanopore") } | set{ nanopore_reads }
        
        // illumina_reads.view { "validate_folder | illumina_files: ${it}" }
        // nanopore_reads.view { "validate_folder | nanopore_files: ${it}" }

        reads = illumina_reads.join(nanopore_reads, remainder: true).map{ create_folder_read_channels(it) }

        //reads = nanopore_reads.map{ create_folder_read_channels(it) }

        //reads.view { "validate_folder | reads: ${it}" }

        BUILD_SHEET(reads).csv.collectFile(name: 'samplesheet.csv', keepHeader: true).map { it }.set { samplesheet }
        
        log.debug "Folder is good ✅"

    emit:
        reads // channel: [ val(meta), [ illumina ], nanopore ]
        samplesheet
        versions = BUILD_SHEET.out.versions

}

process BUILD_SHEET {
    tag "$folder"
    label 'process_medium'

    conda "conda-forge::python=3.9.5"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1' :
        'biocontainers/python:3.9--1' }"

    input:
        tuple val(id), val(illumina1), val(illumina2), val(nanopore)

    output:
        path '*.csv'       , emit: csv
        path "versions.yml", emit: versions

    when:
        task.ext.when == null || task.ext.when

    script: // This script is bundled with the pipeline, in nf-core/rnaseq/bin/
        """
        touch ${id}_samplesheet.csv
        echo "ID,illumina1,illumina2,nanopore" >> ${id}_samplesheet.csv
        echo "${id},${illumina1},${illumina2},${nanopore}" >> ${id}_samplesheet.csv

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            python: \$(python --version | sed 's/Python //g')
        END_VERSIONS
        """
}

// Function to get list of [ meta, illumina1, illumina2, nanopore ]
def create_folder_read_channels(List row) {

    id = row[0]
    illumina1 = row[1]
    illumina2 = row.size() == 3 ? "" : row[2]
    nanopore = row.size() == 3 ? row[2] : row[3]
    
    array = [ id, illumina1, illumina2, nanopore ]
    array = array.stream().map(x -> (x == null)? "":x).collect()

    return array
}

// def createSampleSheet(fileName) {
//     import org.apache.commons.csv.CSVPrinter
//     def FILE_HEADER = ['ID','illumina1','illumina2','nanopore']    
//     def csvFilePrinter = new CSVPrinter(fileWriter, CSVFormat.DEFAULT)
//     csvFilePrinter.printRecord(FILE_HEADER)
//     reads.each{ read -> csvFilePrinter.printRecord(read)}
//     return
// }

def checkReads(List row, platform = null) {
    def meta = [:]
    id = row[0]
    reads = row[1..row.size()-1]
    files = []

    // log.debug "Checking platform:"
    // log.debug platform

    if (reads.size()) {       
        for (read in reads) {
            if (read == 'NA' | read == '') return 'NA'
            if (!file(read).exists())    exit 1, "ERROR: Please check input samplesheet -> FASTQ file does not exist!\n   ${read}"        
            if (file(read).size() == 0)  exit 1, "ERROR: Please check input samplesheet -> FASTQ file is empty!\n   ${read}"
            files << file(read)
        }
    } else {
        files = [""]
    }

    if (platform.equalsIgnoreCase('illumina')) {
        if (files.size() == 2) {
            reads = [id, files[0], files[1] ]
        } else {
            reads = [id, files.join(";") , "" ]
        }
    } else {
        reads = [id, files.join(";") ]
    }

    return reads
}