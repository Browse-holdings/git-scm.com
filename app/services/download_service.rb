require 'rss'

class DownloadService
  # [OvD] note that Google uses Atom & Sourceforge uses RSS
  # however this isn't relevant when parsing the feeds for
  # name, version, url & date with Feedzirra
  SOURCEFORGE_URL = 'https://sourceforge.net/projects/git-osx-installer/rss?limit=20'.freeze

  GIT_FOR_WINDOWS_REGEX           = /^(Portable|)Git-(\d+\.\d+\.\d+(?:\.\d+)?)-(?:.+-)*(32|64)-bit(?:\..*)?\.exe/
  GIT_FOR_WINDOWS_NAME_WITH_OWNER = 'git-for-windows/git'.freeze

  class << self
    def sourceforge_project_download_url(project, filename)
      "https://sourceforge.net/projects/#{project}/files/#{filename}/download?use_mirror=autoselect"
    end

    def download_windows_versions
      files_from_github(GIT_FOR_WINDOWS_NAME_WITH_OWNER).each do |name, date, url|
        # Git for Windows uses the following naming system
        # [Portable]Git-#.#.#.#[-dev-preview]-32/64-bit[.7z].exe
        match = GIT_FOR_WINDOWS_REGEX.match(name)

        next unless match

        portable = match[1]
        bitness  = match[3]

        version = find_or_create_version_by_name(name)

        find_or_create_download(
          filename:     name,
          platform:     "windows#{bitness}#{portable}",
          release_date: date,
          version:      version,
          url:          url
        )
      end
    end

    def download_mac_versions
      files_from_sourceforge(SOURCEFORGE_URL).each do |url, date|
        name  = url.split('/')[-2]
        match = /git-(.*?)-/.match(name)

        next unless match

        url  = sourceforge_project_download_url('git-osx-installer', name)
        name = match[1]

        version = find_or_create_version_by_name(name)

        find_or_create_download(
          filename:     name,
          platform:     'mac',
          release_date: date,
          version:      version,
          url:          url
        )
      end
    end

    private

    def files_from_github(repository)
      downloads = []
      releases  = Octokit.client.releases(repository)

      releases.each do |release|
        release.assets.each do |asset|
          downloads << [
            asset.name,
            asset.updated_at,
            asset.browser_download_url
          ]
        end
      end

      downloads
    end

    def files_from_sourceforge(repository)
      downloads = []
      rss       = open(repository).read
      feed      = RSS::Parser.parse(rss)

      feed.items.each do |item|
        downloads << [item.link, item.pubDate]
      end

      downloads
    end

    def find_or_create_download(filename:, platform:, release_date:, version:, url:)
      options = {
        filename:     filename,
        platform:     platform,
        release_date: release_date,
        version:      version,
        url:          url
      }

      if (download = Download.find_by(options))
        Rails.logger.info("[SUCCESS] Download record found #{download.inspect}")
      else
        begin
          download = Download.create!(options)
          Rails.logger.info("[SUCCESS] Download record created #{download.inspect}")
        rescue ActiveRecord::RecordInvalid => e
          Rail.logger.error("[FAILURE] #{e.message}")
        end
      end
    end

    def find_or_create_version_by_name(name)
      Version.find_by(name: name) || Version.create(name: name)
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end
end
