import Foundation
import BoltsSwift

public class APIClient: NSObject, NetworkClient {
    
    public typealias HTTPResponse = (HTTPURLResponse, Data)
    
    private let responseExecutor: Executor = .queue(DispatchQueue(label: Bundle.main.bundleIdentifier!, attributes: .concurrent))
    private let requestExecutor: RequestExecutor
    private let deserializer: Deserializer
    private let errorProcessor: APIErrorProcessing = APIErrorProcessor()
    private var credentialsProducer: CredentialsProducing?
    private var requestDecorator: RequestDecorator?
    
    // MARK: - Init
    
    public init(requestExecutor: RequestExecutor, deserializer: Deserializer = JSONDeserializer(), credentialsProducer: CredentialsProducing? = nil, requestDecorator: RequestDecorator? = nil) {
        self.requestExecutor = requestExecutor
        self.deserializer = deserializer
        self.credentialsProducer = credentialsProducer
        self.requestDecorator = requestDecorator
    }
    
    // MARK: - Request
    
    private func validate(_ response: HTTPResponse) -> Task<HTTPResponse> {
        switch response.0.statusCode {
        case (200...299):
            return Task<HTTPResponse>(response)
        default:
            return Task<HTTPResponse>(error: errorProcessor.processErrorWithResponse(response))
        }
    }
    
    private func decoratedRequest(from request: APIRequest) -> APIRequest {
        let decoratedRequest: APIRequest
        if let requestDecorator = requestDecorator {
            decoratedRequest = requestDecorator.decoratedRequest(from: request)
        } else {
            decoratedRequest = request
        }
        
        return decoratedRequest
    }
    
    private static var recoverableErrors: Set<NetworkError> {
        return Set<NetworkError>([NetworkError(code: .unauthorized)])
    }
    
    private func canRecover(from error: NetworkError) -> Bool {
        return type(of: self).recoverableErrors.contains(error)
    }
    
    private func _execute<T, U: ResponseParser>(_ requestTaskProducer: @escaping (Void) -> Task<HTTPResponse>, parser: U) -> Task<T> where U.Representation == T {
        let deserializer = self.deserializer
        
        let requestTask = requestTaskProducer()
        func validatedTask(from task: Task<HTTPResponse>) -> Task<HTTPResponse> {
            return task.continueWithTask(continuation: { responseTask in
                if let response = responseTask.result {
                    return self.validate(response)
                }
                
                return responseTask
            })
        }
        
        return validatedTask(from: requestTask).continueOnErrorWithTask(continuation: { error -> Task<HTTPResponse> in
            if let error = error as? NetworkError, let credentialsProducer = self.credentialsProducer , self.canRecover(from: error) {
                
                return credentialsProducer.restoreCredentials().continueWithTask { task -> Task<HTTPResponse> in
                    if let result = task.result, result {
                        return validatedTask(from: requestTaskProducer())
                    } else {
                        return Task(error: error)
                    }
                }
            } else {
                return Task(error: error)
            }
        }).continueOnSuccessWith(responseExecutor, continuation: { response, data -> AnyObject in
            return try deserializer.deserialize(response, data: data)
        }).continueOnSuccessWith(responseExecutor, continuation: { response in
            return try parser.parse(response)
        }).continueOnSuccessWith(.mainThread, continuation: { response in
            return response
        })
    }
    
    // MARK: Request Execution
    
    public func execute<T, U: ResponseParser>(request: APIRequest, parser: U) -> Task<T> where U.Representation == T {
        return _execute({
                return self.requestExecutor.execute(request: self.decoratedRequest(from: request))
            },
            parser: parser
        )
    }
        
    public func execute<T: SerializeableAPIRequest>(request: T) -> Task<T.Parser.Representation> {
        return execute(request: request, parser: request.parser)
    }
    
    // MARK: Multipart Request Execution
    
    public func execute<T, U: ResponseParser>(multipartRequest: APIRequest, parser: U) -> Task<T> where U.Representation == T {
        return _execute({
                self.requestExecutor.execute(multipartRequest: self.decoratedRequest(from: multipartRequest))
            },
            parser: parser
        )
    }
    
    public func execute<T: SerializeableAPIRequest>(multipartRequest: T) -> Task<T.Parser.Representation> {
        return execute(multipartRequest: multipartRequest, parser: multipartRequest.parser)
    }
    
}

