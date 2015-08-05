module Lita
  module Handlers
    class Artifactory < Handler
      config :username, required: true
      config :password, required: true
      config :endpoint, required: true
      config :base_path, default: 'com/getchef'
      config :ssl_pem_file, default: nil
      config :ssl_verify, default: nil
      config :proxy_username, default: nil
      config :proxy_password, default: nil
      config :proxy_address, default: nil
      config :proxy_port, default: nil

      ARTIFACT = /[\w\-\.\+\_]+/
      VERSION = /[\w\-\.\+\_]+/
      FROM_REPO = /[\w\-]+/
      TO_REPO = /[\w\-]+/
      STABLE_REPO  = 'omnibus-stable-local'

      route(/^artifact(?:ory)?\s+promote\s+#{ARTIFACT.source}\s+#{VERSION.source}\s+from\s+#{FROM_REPO.source}\s+to\s+#{TO_REPO.source}/i, :promote, command: true, help: {
              'artifactory promote' => 'promote <artifact> <version> from <from-repo> to <to-repo>',
            })

      route(/^artifact(?:ory)?\s+repos(?:itories)?/i, :repos, command: true, help: {
              'artifactory repos' => 'list artifact repositories',
            })

      def promote(response)
        project       = response.args[1]
        version       = response.args[2]
        artifact_path = File.join(config.base_path, project, version)
        user          = response.user

        promotion_options = {
          status:  'STABLE',
          comment: 'Promoted using the lita-artifactory plugin. ChatOps FTW!',
          user: "#{user.name} (ID: #{user.id}, Mention name: #{user.mention_name})",
        }

        # attempt to locate the build
        build = ::Artifactory::Resource::Build.find(project, version, client: client)

        # attempt a dry run promotion first
        artifactory_response = build.promote(STABLE_REPO, promotion_options.merge(dry_run: true))

        if artifactory_response['messages'].empty?
          build.promote(STABLE_REPO, promotion_options)

          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            :metal: :ice_cream: *#{project}* *#{version}* has been successfully promoted to *#{STABLE_REPO}*!

            You can view the promoted artifacts at:
            #{config.endpoint}/webapp/browserepo.html?pathId=#{STABLE_REPO}:#{artifact_path}
          EOH
          response.reply reply_msg
        else
          reply_msg = <<-EOH.gsub(/^ {12}/, '')
            :scream: :skull: There was an error promoting *#{project}* *#{version}* to *#{STABLE_REPO}*!

            Full error message from #{config.endpoint}:

            ```#{artifactory_response['messages'].map { |m| m['message'] }.join("\n")}```
          EOH
          response.reply reply_msg
        end
      end

      def repos(response)
        response.reply "Artifact repositories: #{all_repos.collect(&:key).sort.join(', ')}"
      end

      private

      def client
        @client ||= ::Artifactory::Client.new(
          endpoint:       config.endpoint,
          username:       config.username,
          password:       config.password,
          ssl_pem_file:   config.ssl_pem_file,
          ssl_verify:     config.ssl_verify,
          proxy_username: config.proxy_username,
          proxy_password: config.proxy_password,
          proxy_address:  config.proxy_address,
          proxy_port:     config.proxy_port,
        )
      end

      def all_repos
        ::Artifactory::Resource::Repository.all(client: client)
      end
    end

    Lita.register_handler(Artifactory)
  end
end
