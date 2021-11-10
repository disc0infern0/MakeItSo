//
//	TaskRepository.swift
//  MakeItSo
//
//  Created by Peter Friese on 10.11.21.
//  Copyright © 2021 Google LLC. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Combine
import Firebase
import Resolver
import os

class TasksRepository: ObservableObject {
  // MARK: - Dependencies
  @Injected var db: Firestore
  @Injected var authenticationService: AuthenticationService
  
  // MARK: - Publishers
  @Published public var tasks = [Task]()
  
  // MARK: - Private attributes
  private var userId: String = "unknown"
  private var listenerRegistration: ListenerRegistration?
  private var cancellables = Set<AnyCancellable>()
  
  let logger = Logger(subsystem: "dev.peterfriese.MakeItSo.dev", category: "persistence")

  
  init() {
    // observe user ID
    authenticationService.$user
      .compactMap { user in
        user?.uid
      }
      .assign(to: \.userId, on: self)
      .store(in: &cancellables)

    authenticationService.$user
      .receive(on: DispatchQueue.main)
      .sink { [weak self] user in
        if self?.listenerRegistration != nil {
          self?.unsubscribe()
          self?.subscribe()
        }
      }
      .store(in: &cancellables)
  }
  
  deinit {
    unsubscribe()
  }
  
  func unsubscribe() {
    if listenerRegistration != nil {
      listenerRegistration?.remove()
      listenerRegistration = nil
    }
  }
  
  func subscribe() {
    if listenerRegistration != nil {
      unsubscribe()
    }
    let query = db.collection("tasks")
      .whereField("userId", isEqualTo: userId)
    
    listenerRegistration = query
      .addSnapshotListener { [weak self] (querySnapshot, error) in
        guard let documents = querySnapshot?.documents else {
          self?.logger.debug("No documents in 'tasks' collection")
          return
        }
        
        self?.tasks = documents.compactMap { queryDocumentSnapshot in
          let result = Result { try queryDocumentSnapshot.data(as: Task.self) }
          
          switch result {
          case .success(let task):
            if let task = task {
              // A `Task` value was successfully initialized from the DocumentSnapshot.
              return task
            }
            else {
              // A nil value was successfully initialized from the DocumentSnapshot,
              // or the DocumentSnapshot was nil.
              print("Document doesn't exist.")
              return nil
            }
          case .failure(let error):
            // A `Task` value could not be initialized from the DocumentSnapshot.
            switch error {
            case DecodingError.typeMismatch(_, let context):
              self?.logger.error("\(error.localizedDescription): \(context.debugDescription)")
            case DecodingError.valueNotFound(_, let context):
              self?.logger.error("\(error.localizedDescription): \(context.debugDescription)")
            case DecodingError.keyNotFound(_, let context):
              self?.logger.error("\(error.localizedDescription): \(context.debugDescription)")
            case DecodingError.dataCorrupted(let key):
              self?.logger.error("\(error.localizedDescription): \(key.debugDescription)")
            default:
              self?.logger.error("Error decoding document: \(error.localizedDescription)")
            }
            return nil
          }
        }
      }
  }
  
  func addTask(_ task: Task) {
    do {
      var userTask = task
      userTask.userId = userId
      logger.debug("Adding task '\(userTask.title)' for user \(self.userId)")
      let _ = try db.collection("tasks").addDocument(from: userTask)
    }
    catch {
      logger.error("Error: \(error.localizedDescription)")
    }
  }
  
  func updateTask(_ task: Task) {
    if let documentId = task.id {
      do {
        try db.collection("tasks").document(documentId).setData(from: task)
      }
      catch {
        self.logger.debug("Unable to update document \(documentId): \(error.localizedDescription)")
      }
    }
  }
  
  func removeTask(_ task: Task) {
    if let taskID = task.id {
      db.collection("tasks").document(taskID).delete() { error in
        if let error = error {
          self.logger.debug("Unable to remove document \(error.localizedDescription)")
        }
      }
    }
  }



}
