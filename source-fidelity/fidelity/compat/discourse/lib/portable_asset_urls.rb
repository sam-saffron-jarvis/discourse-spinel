# frozen_string_literal: true
# GENERATED source-backed URL helpers; settings are explicit supplied unit inputs.
module PortableAssetUrlMethods
def script_asset_path(script)
    asset_cdn_path("#{script}.js", brotli: true)
  end

def asset_cdn_path(logical_path, brotli: false)
    path = asset_paths.asset_path(logical_path)

    if settings.use_s3? && settings.s3_cdn_url
      resolved_s3_asset_cdn_url =
        (PortableResponseMiddlewareDeclarations.blank_header?(settings.s3_asset_cdn_url) ? nil : settings.s3_asset_cdn_url) || settings.s3_cdn_url
      if settings.cdn_url
        folder = settings.relative_url_root || "/"
        path =
          path.gsub(
            File.join(settings.cdn_url, folder, "/"),
            File.join(resolved_s3_asset_cdn_url, "/"),
          )
      else
        # we must remove the subfolder path here, assets are uploaded to s3
        # without it getting involved
        if settings.relative_url_root
          path = path.sub(settings.relative_url_root, "")
        end

        path = "#{resolved_s3_asset_cdn_url}#{path}"
      end

      path = path.sub("/assets/js/", "/assets/br/") if brotli && is_brotli_req?
    end

    path
  end

def is_brotli_req?
    request.env["HTTP_ACCEPT_ENCODING"] =~ /br/
  end
end
