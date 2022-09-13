//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  ProductsManager.swift
//
//  Created by Andrés Boedo on 7/14/20.
//
import Foundation
import StoreKit

class ProductsManager: NSObject {
	private let productsRequestFactory: ProductsRequestFactory
	private var cachedProductsByIdentifier: [String: SKProduct] = [:]
	private let queue = DispatchQueue(label: "ProductsManager")
	private var productsByRequests: [SKRequest: Set<String>] = [:]
  typealias ProductRequestCompletionBlock = (Result<Set<SKProduct>, Error>) -> Void
	private var completionHandlers: [Set<String>: [ProductRequestCompletionBlock]] = [:]

	init(productsRequestFactory: ProductsRequestFactory = ProductsRequestFactory()) {
		self.productsRequestFactory = productsRequestFactory
	}

	func products(
    withIdentifiers identifiers: Set<String>,
    completion: @escaping ProductRequestCompletionBlock
  ) {
    // Return if there aren't any product IDs.
		if identifiers.isEmpty {
      completion(.success([]))
			return
		}

		queue.async { [self] in
      // If products already cached, return them
      let cachedProducts = Set(self.cachedProductsByIdentifier.map { $0.key })
      let productsToRetrieve = identifiers.subtracting(cachedProducts)

			if productsToRetrieve.isEmpty {
        let productsAlreadyCached = Set(self.cachedProductsByIdentifier.map { $0.value })
				Logger.debug(
          logLevel: .debug,
          scope: .productsManager,
          message: "Products Already Cached",
          info: ["product_ids": identifiers],
          error: nil
        )
        completion(.success(productsAlreadyCached))
				return
			}

      // If there are any existing completion handlers, it means there have already been some requests for products but they haven't loaded. Queue up this request's completion handler.
			if let existingHandlers = self.completionHandlers[productsToRetrieve] {
				Logger.debug(
          logLevel: .debug,
          scope: .productsManager,
          message: "Found Existing Product Request",
          info: ["product_ids": identifiers],
          error: nil
        )
				self.completionHandlers[productsToRetrieve] = existingHandlers + [completion]
				return
			}

      // Otherwise request products and enqueue the completion handler.
      // When the request finishes, all completion handlers will get called with the products.
			Logger.debug(
        logLevel: .debug,
        scope: .productsManager,
        message: "Creating New Request",
        info: ["product_ids": productsToRetrieve],
        error: nil
      )
			let request = self.productsRequestFactory.request(productIdentifiers: productsToRetrieve)
			request.delegate = self
			self.completionHandlers[productsToRetrieve] = [completion]
			self.productsByRequests[request] = productsToRetrieve
			request.start()
		}
	}

	func cacheProduct(_ product: SKProduct) {
		queue.async {
			self.cachedProductsByIdentifier[product.productIdentifier] = product
		}
	}
}

// MARK: - SKProductsRequestDelegate
extension ProductsManager: SKProductsRequestDelegate {
	func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		queue.async { [self] in
			Logger.debug(
        logLevel: .debug,
        scope: .productsManager,
        message: "Fetched Product",
        info: ["request": request.debugDescription],
        error: nil
      )
			guard let requestProducts = self.productsByRequests[request] else {
				Logger.debug(
          logLevel: .warn,
          scope: .productsManager,
          message: "Requested Products Not Found",
          info: ["request": request.debugDescription],
          error: nil
        )
				return
			}
			guard let completionBlocks = self.completionHandlers[requestProducts] else {
				Logger.debug(
          logLevel: .error,
          scope: .productsManager,
          message: "Completion Handler Not Found",
          info: ["products": requestProducts, "request": request.debugDescription],
          error: nil
        )
				return
			}

			self.completionHandlers.removeValue(forKey: requestProducts)
			self.productsByRequests.removeValue(forKey: request)

			self.cacheProducts(response.products)
			for completion in completionBlocks {
        completion(.success(Set(response.products)))
			}
		}
	}

	func requestDidFinish(_ request: SKRequest) {
		Logger.debug(
      logLevel: .debug,
      scope: .productsManager,
      message: "Request Complete",
      info: ["request": request.debugDescription],
      error: nil
    )
		request.cancel()
	}

	func request(_ request: SKRequest, didFailWithError error: Error) {
		queue.async { [self] in
			Logger.debug(
        logLevel: .error,
        scope: .productsManager,
        message: "Request Failed",
        info: ["request": request.debugDescription],
        error: error
      )
			guard let products = self.productsByRequests[request] else {
				Logger.debug(
          logLevel: .error,
          scope: .productsManager,
          message: "Requested Products Not Found",
          info: ["request": request.debugDescription],
          error: error
        )
				return
			}
			guard let completionBlocks = self.completionHandlers[products] else {
				Logger.debug(
          logLevel: .error,
          scope: .productsManager,
          message: "Callback Not Found for Failed Request",
          info: ["request": request.debugDescription],
          error: error
        )
				return
			}

			self.completionHandlers.removeValue(forKey: products)
			self.productsByRequests.removeValue(forKey: request)
			for completion in completionBlocks {
        completion(.failure(error))
			}
		}
		request.cancel()
	}
}

private extension ProductsManager {
	func cacheProducts(_ products: [SKProduct]) {
		let productsByIdentifier = products.reduce(into: [:]) { resultDict, product in
			resultDict[product.productIdentifier] = product
		}

		cachedProductsByIdentifier = cachedProductsByIdentifier.merging(productsByIdentifier)
	}
}


class ProductsRequestFactory {
	func request(productIdentifiers: Set<String>) -> SKProductsRequest {
		return SKProductsRequest(productIdentifiers: productIdentifiers)
	}
}
