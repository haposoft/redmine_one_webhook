module RedmineWebhook
  class AuthorWrapper
    include GravatarHelper::PublicMethods
    include ERB::Util

    def initialize(author)
      @author = author
    end

    def to_hash
      return nil unless @author
      {
        :id => @author.id,
        :login => @author.login,
        :mail => @author.mail,
        :firstname => @author.firstname,
        :lastname => @author.lastname,
        :identity_url => @author.try(:identity_url),
        :icon_url => icon_url
      }
    end

    def icon_url
      return nil if @author.mail.blank?
      gravatar_url(@author.mail)
    end
  end
end
