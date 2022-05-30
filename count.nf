#!/usr/bin/env nextflow
/*
========================================================================================
                         MPRAflow
========================================================================================
MPRA Analysis Pipeline.
Started 2019-07-29.
Count Utility
#### Homepage / Documentation
https://github.com/shendurelab/MPRAflow
#### Authors
Vikram Agarwal <thefinitemachine@gmail.com>
Gracie Gordon <gracie.gordon@ucsf.edu>
Martin Kircher <martin.kircher@bihealth.de>
Max Schubach <max.schubach@bihealth.de>

----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info"""
    =========================================
    shendurelab/MPRAflow v${params.version}
    =========================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run main.nf
    Mandatory arguments:
      --dir                         Fasta directory (must be surrounded with quotes)
      --e, --experiment-file        Experiment csv file

    Recommended (Needed for the full count workflow. Can be neglected when only counts for saturation mutagenesis are needed):
      --design                      Fasta of ordered insert sequences.
      --association                 Pickle dictionary from library association process.

    Options:
      --labels                      tsv with the oligo pool fasta and a group label (ex: positive_control), a single label will be applied if a file is not specified
      --outdir                      The output directory where the results will be saved (default outs)
      --bc-length                   Barcode length (default 15)
      --umi-length                  UMI length (default 10)
      --no-umi                      Use this flag if no UMI is present in the experiment (default with UMI)
      --merge_intersect             Only retain barcodes in RNA and DNA fraction (TRUE/FALSE, default: FALSE)
      --mpranalyze                  Only generate MPRAnalyze outputs
      --thresh                      minimum number of observed barcodes to retain insert (default 10)

    Extras:
      --h, --help                   Print this help message
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --name                        Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.
    """.stripIndent()
}

/*
* SET UP CONFIGURATION VARIABLES
*/

// Show help message
if (params.containsKey('h') || params.containsKey('help')){
    helpMessage()
    exit 0
}


// Configurable variables
params.name = false
params.email = false
params.plaintext_email = false
output_docs = file("$baseDir/docs/output.md")

//defaults
results_path = params.outdir

params.merge_intersect=false
params.mpranalyze=false
params.thresh=10

// Validate Inputs

// experiment file saved in params.experiment_file
if (params.containsKey('e')){
    params.experiment_file=file(params.e)
} else if (params.containsKey("experiment-file")) {
    params.experiment_file=file(params["experiment-file"])
} else {
    exit 1, "Experiment file not specified with --e or --experiment-file"
}
if( !params.experiment_file.exists()) exit 1, "Experiment file ${params.experiment_file} does not exist"

// design file saved in params.design_file
if ( params.containsKey("design")){
    params.design_file=file(params.design)
    if( !params.design_file.exists() ) exit 1, "Design file ${params.design} does not exist"
    if( !params.containsKey("association") ) exit 1, "Association file has to be specified with --association when using option --design"
} else if (params.mpranalyze) {
    exit 1, "Design file has to be specified with --association when using flag --mpranalyze"
} else {
    log.info("Running MPRAflow count without design file.")
}

// Association file in params.association_file
if (params.containsKey("association")){
    params.association_file=file(params.association)
    if( !params.association_file.exists() ) exit 1, "Association pickle ${params.association_file} does not exist"
} else if (params.mpranalyze) {
    exit 1, "Association file has to be specified with --association when using flag --mpranalyze"
} else {
    log.info("Running MPRAflow count without association file.")
}

// label file saved in label_file
if (params.containsKey("labels")){
    label_file=file(params.labels)
    if (!label_file.exists()) {
      println "Label file ${label_file} does not exist. Use NA as label!"
      label_file=file("NA")
    }
} else {
    label_file=file("NA")
}

// check if UMIs or not are present
if (params.containsKey("no-umi")){
    params.no_umi = true
} else {
    params.no_umi = false
}

// BC length
if (params.containsKey("bc-length")){
    params.bc_length = params["bc-length"]
} else {
    params.bc_length = 15
}
// UMI length
if (params.containsKey("umi-length")){
    params.umi_length = params["umi-length"]
} else {
    params.umi_length = 10
}

// Create FASTQ channels
if (params.no_umi) {
  reads_noUMI = Channel.fromPath(params.experiment_file).splitCsv(header: true).flatMap{
    row -> [
      tuple(row.Condition,row.Replicate,"DNA",
        [row.Condition,row.Replicate,"DNA"].join("_"),
        file([params.dir,"/",row.DNA_BC_F].join()),
        file([params.dir,"/",row.DNA_BC_R].join())
      ),
      tuple(row.Condition,row.Replicate,"RNA",
        [row.Condition,row.Replicate,"RNA"].join("_"),
        file([params.dir,"/",row.RNA_BC_F].join()),
        file([params.dir,"/",row.RNA_BC_R].join())
      )
    ]
  }
} else {
  reads = Channel.fromPath(params.experiment_file).splitCsv(header: true).flatMap{
    row -> [
      tuple(row.Condition, row.Replicate, "DNA",
        [row.Condition,row.Replicate,"DNA"].join("_"),
        file([params.dir,"/",row.DNA_BC_F].join()),
        file([params.dir,"/",row.DNA_UMI].join()),
        file([params.dir,"/",row.DNA_BC_R].join()),
      ),
      tuple(row.Condition, row.Replicate, "RNA",
        [row.Condition,row.Replicate,"RNA"].join("_"),
        file([params.dir,"/",row.RNA_BC_F].join()),
        file([params.dir,"/",row.RNA_UMI].join()),
        file([params.dir,"/",row.RNA_BC_R].join()),
      ),
    ]
  }
}


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}



// Header log info
log.info """=======================================================
                                          ,--./,-.
          ___     __   __   __   ___     /,-._.--~\'
    |\\ | |__  __ /  ` /  \\ |__) |__         }  {
    | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                          `._,._,\'
MPRAflow v${params.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']    = 'shendurelab/MPRAflow'
summary['Pipeline Version'] = params.version
summary['Run Name']         = custom_runName ?: workflow.runName

//summary['Thread fqdump']    = params.threadfqdump ? 'YES' : 'NO'
summary['Output dir']       = params.outdir
summary['Working dir']      = workflow.workDir
//summary['Container Engine'] = workflow.containerEngine
//if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']     = "$HOME"
summary['Current user']     = "$USER"
summary['Current path']     = "$PWD"
summary['Working dir']      = workflow.workDir
summary['Output dir']       = params.outdir
summary['Script dir']       = workflow.projectDir
summary['Config Profile']   = workflow.profile
summary['Experiment File']  = params.experiment_file
summary['reads']            = (params.no_umi ? reads_noUMI : reads)
summary['UMIs']             = (params.no_umi ? "Reads without UMI" : "Reads with UMI")
summary['BC length']        = params.bc_length
summary['BC threshold']     = params.thresh
summary['mprAnalyze']       = params.mpranalyze

if(params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="

// Check that Nextflow version is up to date enough
// try / throw / catch works for NF versions < 0.25 when this was implemented
try {
    if( ! nextflow.version.matches(">= $params.nf_required_version") ){
        throw GroovyException('Nextflow version too old')
    }
} catch (all) {
    log.error "====================================================\n" +
              "  Nextflow version $params.nf_required_version required! You are running v$workflow.nextflow.version.\n" +
              "  Pipeline execution will continue, but things may break.\n" +
              "  Please run `nextflow self-update` to update Nextflow.\n" +
              "============================================================"
}

println 'start analysis'

/*
* STEP 1: Create BAM files
* contributions: Martin Kircher, Max Schubach, & Gracie Gordon
*/
//if UMI
if (!params.no_umi) {
    process 'create_BAM' {
        tag "make idx"
        label 'longtime'

        conda 'conf/mpraflow_py27.yml'

        input:
            tuple val(cond), val(rep), val(type), val(datasetID), file(fw_fastq), file(umi_fastq), file(rev_fastq) from reads
            val(bc_length) from params.bc_length
        output:
            tuple val(cond), val(rep), val(type),val(datasetID),file("${datasetID}.bam") into clean_bam
        shell:
            """
            #!/bin/bash
            echo $datasetID

            echo $fw_fastq
            echo $umi_fastq
            echo $rev_fastq

            umi_length=`zcat $umi_fastq | head -2 | tail -1 | wc -c`
            umi_length=\$(expr \$((\$umi_length-1)))

            fwd_length=`zcat $fw_fastq | head -2 | tail -1 | wc -c`
            fwd_length=\$(expr \$((\$fwd_length-1)))

            rev_start=\$(expr \$((\$fwd_length+1)))

            rev_length=`zcat $rev_fastq | head -2 | tail -1 | wc -c`
            rev_length=\$(expr \$((\$rev_length-1)))

            minoverlap=`echo \${fwd_length} \${fwd_length} $bc_length | awk '{print (\$1+\$2-\$3-1 < 11) ? \$1+\$2-\$3-1 : 11}'`

            echo \$rev_start
            echo \$umi_length
            echo \$minoverlap

            paste <( zcat $fw_fastq ) <( zcat $rev_fastq  ) <( zcat $umi_fastq ) | awk '{if (NR % 4 == 2 || NR % 4 == 0) {print \$1\$2\$3} else {print \$1}}' | python ${"$baseDir"}/src/FastQ2doubleIndexBAM.py -p -s \$rev_start -l 0 -m \$umi_length --RG ${datasetID} | python ${"$baseDir"}/src/MergeTrimReadsBAM.py --FirstReadChimeraFilter '' --adapterFirstRead '' --adapterSecondRead '' -p --mergeoverlap --minoverlap \$minoverlap > ${datasetID}.bam
            """
    }
}

//if no UMI
/*
* contributions: Martin Kircher, Max Schubach, & Gracie Gordon
*/
if (params.no_umi) {
    process 'create_BAM_noUMI' {
        tag "make idx"
        label 'longtime'

        conda 'conf/mpraflow_py27.yml'

        input:
            tuple val(cond), val(rep),val(type),val(datasetID),file(fw_fastq), file(rev_fastq) from reads_noUMI
            val(bc_length) from params.bc_length
        output:
            tuple val(cond), val(rep),val(type),val(datasetID),file("${datasetID}.bam") into clean_bam
        when:
            params.no_umi
        shell:
            """
            #!/bin/bash
            echo $datasetID

            echo $fw_fastq
            echo $rev_fastq

            fwd_length=`zcat $fw_fastq | head -2 | tail -1 | wc -c`
            fwd_length=\$(expr \$((\$fwd_length-1)))

            rev_start=\$(expr \$((\$fwd_length+1)))

            rev_length=`zcat $rev_fastq | head -2 | tail -1 | wc -c`
            rev_length=\$(expr \$((\$rev_length-1)))

            minoverlap=`echo \${fwd_length} \${fwd_length} $bc_length | awk '{print (\$1+\$2-\$3-1 < 11) ? \$1+\$2-\$3-1 : 11}'`

            echo \$rev_start
            echo \$minoverlap

            paste <( zcat $fw_fastq ) <(zcat $rev_fastq  ) | \
            awk '{
                if (NR % 4 == 2 || NR % 4 == 0) {
                  print \$1\$2
                } else {
                  print \$1
                }}' | python ${"$baseDir"}/src/FastQ2doubleIndexBAM.py -p -s \$rev_start -l 0 -m 0 --RG ${datasetID} | python ${"$baseDir"}/src/MergeTrimReadsBAM.py --FirstReadChimeraFilter '' --adapterFirstRead '' --adapterSecondRead '' -p --mergeoverlap  --minoverlap \$minoverlap> ${datasetID}.bam
              """
    }
}


/*
* STEP 2: create raw counts
* contributions: Martin Kircher, Max Schubach, & Gracie Gordon
*/

process 'raw_counts'{
    label 'shorttime'

    conda 'conf/mpraflow_py36.yml'

    publishDir "$params.outdir/$cond/$rep"

    input:
        tuple val(cond), val(rep),val(type),val(datasetID),file(bam) from clean_bam
        val(umi_length) from params.umi_length
    output:
        tuple val(cond), val(rep),val(type),val(datasetID),file("${datasetID}_raw_counts.tsv.gz") into raw_ct
    script:
        if(params.no_umi)
            """
            #!/bin/bash

            samtools view -F 1 -r $datasetID $bam | \
            awk '{print \$10}' | \
            sort | \
            gzip -c > ${datasetID}_raw_counts.tsv.gz
            """

        else
            """
            #!/bin/bash

            samtools view -F 1 -r $datasetID $bam | \
            awk -v 'OFS=\\t' '{ for (i=12; i<=NF; i++) {
              if (\$i ~ /^XJ:Z:/) print \$10,substr(\$i,6,$umi_length)
            }}' | \
            sort | uniq -c | \
            awk -v 'OFS=\\t' '{ print \$2,\$3,\$1 }' | \
            gzip -c > ${datasetID}_raw_counts.tsv.gz
            """

}

/*
* STEP 3: Filter counts for correct barcode length
* contributions: Martin Kircher, Max Schubach, & Gracie Gordon
*/

process 'filter_counts'{
    label 'shorttime'
    publishDir "$params.outdir/$cond/$rep"

    conda 'conf/mpraflow_py27.yml'

    input:
        tuple val(cond), val(rep),val(type),val(datasetID),file(rc) from raw_ct
        val(bcLength) from params.bc_length
    output:
        tuple val(cond), val(rep),val(type),val(datasetID),file("${datasetID}_filtered_counts.tsv.gz") into filter_ct
    shell:
        """
        bc=$bcLength
        echo \$bc
        zcat $rc | grep -v "N" | \
        awk -v var="\$bc" -v 'OFS=\t' '{ if (length(\$1) == var) { print } }' | \
        gzip -c > ${datasetID}_filtered_counts.tsv.gz
        """

}

/*
* STEP 4: Record overrepresended UMIs and final count table
* contributions: Martin Kircher, Max Schubach, & Gracie Gordon
*/

process 'final_counts'{
    label 'shorttime'
    publishDir "$params.outdir/$cond/$rep"

    input:
        tuple val(cond), val(rep),val(type),val(datasetID),file(fc) from filter_ct
    output:
        tuple val(cond), val(rep),val(type),val(datasetID),file("${datasetID}_counts.tsv") into final_count, final_count_satMut
    script:
        if(params.no_umi)
            """
            #!/bin/bash

            zcat $fc | awk '{print \$1}' | \
            uniq -c > ${datasetID}_counts.tsv

            """
        else
            """
            #!/bin/bash

            for i in $fc; do
              echo \$(basename \$i);
              zcat \$i | cut -f 2 | sort | uniq -c | sort -nr | head;
              echo;
            done > ${params.outdir}/${cond}/${rep}/${datasetID}_freqUMIs.txt

            zcat $fc | awk '{print \$1}' | uniq -c > ${datasetID}_counts.tsv
        """

}

/*
* STEP 5: MPRAnalyze input generation (if option selected)
* contributions: Gracie Gordon
*/
process 'dna_rna_merge_counts'{
    publishDir "$params.outdir/$cond/$rep", mode:'copy'
    label 'shorttime'

    conda 'conf/mpraflow_py36.yml'

    input:
        tuple val(cond),val(rep),val(typeA),val(typeB),val(datasetIDA),val(datasetIDB),file(countA),file(countB) from final_count_satMut.groupTuple(by: [0,1]).map{i -> i.flatten()}
    output:
        tuple val(cond), val(rep), file("${cond}_${rep}_counts.tsv.gz") into merged_dna_rna
    script:
        def dna = typeA == 'DNA' ? countA : countB
        def rna = typeA == 'DNA' ? countB : countA
        """
        join -1 1 -2 1 -t"\$(echo -e '\\t')" \
        <( cat  $dna | awk 'BEGIN{ OFS="\\t" }{ print \$2,\$1 }' | sort ) \
        <( cat $rna | awk 'BEGIN{ OFS="\\t" }{ print \$2, \$1 }' | sort) | \
        gzip -c > ${cond}_${rep}_counts.tsv.gz
        """
}


//MPRAnalyze option
//contributions: Gracie Gordon
if(params.mpranalyze){
    /*
    * STEP 5: Merge each DNA and RNA file
    */
    process 'dna_rna_mpranalyze_merge'{
        publishDir "$params.outdir/$cond/$rep", mode:'copy'
        label 'longtime'

        conda 'conf/mpraflow_py36.yml'

        input:
            tuple val(cond),val(rep),val(typeA),val(typeB),val(datasetIDA),val(datasetIDB),file(countA),file(countB) from final_count.groupTuple(by: [0,1]).map{i -> i.flatten()}
        output:
            tuple val(cond), val(rep), file("${cond}_${rep}_counts.csv") into merged_ch
        shell:
            """
            python ${"$baseDir"}/src/merge_counts.py ${typeA} ${countA} ${countB} ${cond}_${rep}_counts.csv
            """
    }


    /*
    * STEP 6: Merge all DNA/RNA counts into one big file
    * contributions: Gracie Gordon
    */

    process 'final_merge'{
        label 'longtime'
        publishDir "$params.outdir/$cond", mode:'copy'

        conda 'conf/mpraflow_py36.yml'

        result = merged_ch.groupTuple(by: 0).multiMap{i ->
                                  cond: i[0]
                                  replicate: i[1]
                                  files: i[2]
                                }

        input:
            file(pairlistFiles) from result.files
            val(replicate) from result.replicate
            val(cond) from result.cond
        output:
            tuple val(cond),file("${cond}_count.csv") into merged_out
        script:
            inputs = [["--counts"]*replicate.size(),replicate,pairlistFiles.collect{"$it"}].transpose().flatten().join(' ')
        shell:
            """
            export LC_ALL=en_US.utf-8
            export LANG=en_US.utf-8
            python ${"$baseDir"}/src/merge_all.py --condition $cond --output "${cond}_count.csv" $inputs
            """
    }


    /*
    * STEP 7: Add label to outfile
    * contributions: Gracie Gordon
    */

    process 'final_label'{
        label 'shorttime'
        publishDir "$params.outdir/$cond", mode:'copy'

        conda 'conf/mpraflow_py36.yml'

        input:
            tuple val(cond), file(table) from merged_out
            file(des) from params.design_file
            file(association) from params.association_file
        output:
            tuple val(cond), file("${cond}_final_labeled_counts.txt") into labeled_out
        shell:
            """
            python ${"$baseDir"}/src/label_final_count_mat.py $table $association "${cond}_final_labeled_counts.txt" $des
            """
    }

    /*
    * STEP 8: Generate inputs
    * contributions: Tal Ashuach
    */

    process 'generate_mpranalyze_inputs'{
        label 'shorttime'
        publishDir "$params.outdir/$cond", mode:'copy'

        conda 'conf/mpraflow_py36.yml'

        input:
            tuple val(cond),file(labeled_file) from labeled_out
        output:
            file("rna_counts.tsv") into mpranalyze_rna_counts
            file("dna_counts.tsv") into mpranalyze_dna_counts
            file("rna_annot.tsv") into mpranalyze_rna_annotation
            file("dna_annot.tsv") into mpranalyze_fna_annotation
        shell:
            """
            python ${"$baseDir"}/src/mpranalyze_compiler.py $labeled_file
            """
    }

}


/*
* STEP 5: Merge each DNA and RNA file label with sequence and insert and normalize
* contributions: Gracie Gordon
*/
//merge and normalize
if(!params.mpranalyze && params.containsKey("association")){

    process 'dna_rna_merge'{
        label 'longtime'
        publishDir "$params.outdir/$cond/$rep", mode:'copy'

        conda 'conf/mpraflow_py36.yml'

        input:
            tuple val(cond), val(rep),val(typeA),val(typeB),val(datasetIDA),val(datasetIDB),file(countA),file(countB) from final_count.groupTuple(by: [0,1]).map{i -> i.flatten()}
            file(des) from params.design_file
            file(association) from params.association_file
            val(bc_length) from params.bc_length
        output:
             tuple val(cond), val(rep), file("${cond}_${rep}_counts.tsv") into merged_ch, merged_ch2
        shell:
            """
            python ${"$baseDir"}/src/merge_label.py --control-type ${typeA} --control ${countA} --experiment ${countB}  \
            --coord $association --design $des \
            --merge-intersect ${params.merge_intersect} --bc-length ${bc_length} \
            --output ${cond}_${rep}_counts.tsv
            """

    }

    /*
    * STEP 6: Calculate correlations between Replicates
    * contributions: Vikram Agarwal & Gracie Gordon
    */
    process 'calc_correlations'{
        label 'shorttime'
        publishDir "$params.outdir/$cond", mode:'copy'

        conda 'conf/mpraflow_r.yml'

        result = merged_ch.groupTuple(by: 0).multiMap{i ->
                                  cond: i[0]
                                  replicate: i[1].join(" ")
                                  files: i[2]
                                }

        input:
            file(pairlistFiles) from result.files
            val(replicate) from result.replicate
            val(cond) from result.cond
            file(lab) from label_file
        output:
            file "*.png"
            file "*_correlation.txt"
        script:
            pairlist = pairlistFiles.collect{"$it"}.join(' ')
            def label = lab.exists() ? lab : lab.name
            """
            Rscript ${"$baseDir"}/src/plot_perInsertCounts_correlation.R $cond $label $params.thresh $pairlist $replicate
            """
    }
    /*
    * contributions: Vikram Agarwal & Gracie Gordon
    */
    process 'make_master_tables' {
        label 'shorttime'
        publishDir "$params.outdir/$cond", mode:'copy'

        conda 'conf/mpraflow_r.yml'

        result = merged_ch2.groupTuple(by: 0).multiMap{i ->
                                  cond: i[0]
                                  replicate: i[1].join(" ")
                                  files: i[2]
                                }

        input:
            file(pairlistFiles) from result.files
            val(replicate) from result.replicate
            val(cond) from result.cond
        output:
            file "average_allreps.tsv"
            file "allreps.tsv"
        script:
            pairlist = pairlistFiles.collect{"$it"}.join(' ')
        shell:
            """
            Rscript ${"$baseDir"}/src/make_master_tables.R $cond $params.thresh allreps.tsv average_allreps.tsv $pairlist $replicate
            """
    }

}


/*
* Completion e-mail notification
*/

/*
workflow.onComplete {
    // Set up the e-mail variables
    def subject = "[NCBI-Hackathons/ATACFlow] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[NCBI-Hackathons/ATACFlow] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = params.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp
    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()
    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()
    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", attach1: "$baseDir/results/Documentation/pipeline_report.html", attach2: "$baseDir/results/pipeline_info/NCBI-Hackathons/ATACFlow_report.html", attach3: "$baseDir/results/pipeline_info/NCBI-Hackathons/ATACFlow_timeline.html" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()
    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[NCBI-Hackathons/ATACFlow] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[NCBI-Hackathons/ATACFlow] Sent summary e-mail to $params.email (mail)"
        }
    }
    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/Documentation/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }
    log.info "[NCBI-Hackathons/ATACFlow] Pipeline Complete"
}
*/
