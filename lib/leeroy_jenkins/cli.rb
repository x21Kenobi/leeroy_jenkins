module LeeroyJenkins
  class Cli < Thor
    class_option :log_level,    required: false, type: :numeric, desc: 'The detail of the messages logged by the Jenkins API client. DEBUG (0), INFO (1), WARN (2), FATAL (3)', enum: [0, 1, 2, 3], default: 3
    class_option :log_location, required: false, type: :string,  desc: 'Path to the log file', default: STDOUT
    class_option :username,     required: false, type: :string,  desc: 'Override LEEROY_JENKINS_USERNAME'
    class_option :password,     required: false, type: :string,  desc: 'Override LEEROY_JENKINS_PASSWORD'
    class_option :server_url,   required: false, type: :string,  desc: 'Override LEEROY_JENKINS_SERVER_URL'
    class_option :threads,      required: false, type: :numeric, desc: 'Number of threads to use for network and disk IO', default: 4

    desc 'update-config', 'Modify jobs\' config.xml'
    option :job_regex, required: false, type: :string,  desc: 'Regular expression to select jobs by name', default: '.*'
    option :new_xml,   required: true,  type: :string,  desc: 'Path to an XML file'
    option :xpath,     required: false, type: :string,  desc: 'XPath of node(s) to modify in the config.xml of the specified job(s)', default: '/'
    option :dry_run,                    type: :boolean, desc: 'Write XML to STDOUT instead of to Jenkins', default: true
    option :at_xpath,  required: false, type: :string,  desc: 'Replace, append to, or delete the XML node(s) specified by the given XPath', enum: ['replace', 'append', 'delete'], default: 'replace'
    def update_config
      raw_xml_string = File.read options[:new_xml]
      if error = LeeroyJenkins.invalid_xml_document?(raw_xml_string)
        error "#{options[:new_xml]}} is not well-formed XML: #{error}"
        exit 1
      end

      jenkins_client = build_jenkins_client options

      job_names_to_update = JobFinder.new(options[:job_regex], jenkins_client).find_jobs
      job_updater = JobUpdater.new job_names_to_update, raw_xml_string, jenkins_client, options[:xpath], options[:at_xpath], options[:threads]
      result = options[:dry_run] ? job_updater.dry_run : job_updater.update_jobs!

      if options[:dry_run]
        result.each do |key, value|
          puts "#{key}:"
          puts
          puts value
        end
      else
        result.each do |key, value|
          puts "#{key}: #{value}"
        end
      end
    end

    desc 'backup', 'Save the config.xml of Jenkins jobs to disk'
    option :job_regex,  required: false, type: :string, desc: 'Regular expression to select jobs by name', default: '.*'
    option :backup_dir, required: true,  type: :string, desc: 'Path to the directory to save the config.xml file to, created if it does not exist'
    def backup
      jenkins_client = build_jenkins_client options
      job_names_to_backup = JobFinder.new(options[:job_regex], jenkins_client).find_jobs
      JobBackupper.new(job_names_to_backup, jenkins_client, options[:backup_dir], options[:threads]).backup
    end

    desc 'restore', 'Restore config.xml files to Jenkins jobs from backups'
    option :backup_dir, required: true, type: :string,  desc: 'Path to the directory where config.xml files were backed up'
    option :dry_run,                    type: :boolean, desc: 'Write XML to STDOUT instead of to Jenkins', default: true
    def restore
      jenkins_client = build_jenkins_client options
      job_restorer = JobRestorer.new jenkins_client, options[:backup_dir], options[:threads]
      result = options[:dry_run] ? job_restorer.dry_run : job_restorer.restore!

      if options[:dry_run]
        result.each do |key, value|
          puts "#{key}:"
          puts
          puts value
        end
      else
        result.each do |key, value|
          puts "#{key}: #{value}"
        end
      end
    end

    private

    def build_jenkins_client options
      JenkinsClientBuilder.new(
        server_url: options[:server_url],
        username: options[:username],
        password: options[:password],
        log_level: options[:log_level],
        log_location: options[:log_location]
      ).build
    end

  end
end
