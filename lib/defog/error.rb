module Defog
  class Error < RuntimeError

    class NoCloudFile < Error
    end

    class CacheFull < Error
    end
  end

end
