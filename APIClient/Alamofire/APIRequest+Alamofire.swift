import Foundation
import Alamofire

public extension APIRequest {

    // FIXME: looks shitty
    // don't know why `APIRequestMethod` is a type of `UInt`
    // let's try to make it of `String` type and convert it's rawValue into Alamofire's `HTTPMethod` in this method
    public var alamofireMethod: HTTPMethod {
        switch method {
        case .options:
            return .options

        case .get:
            return .get

        case .head:
            return .head

        case .post:
            return .post

        case .put:
            return .put

        case .patch:
            return .patch

        case .delete:
            return .delete

        case .trace:
            return .trace

        case .connect:
            return .connect
        }
    }

    public var alamofireEncoding: ParameterEncoding {
        return encoding as? ParameterEncoding ?? URLEncoding.default
    }
    
}

extension URLEncoding: APIRequestEncoding {}
extension PropertyListEncoding: APIRequestEncoding {}
extension JSONEncoding: APIRequestEncoding {}
